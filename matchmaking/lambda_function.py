"""room directory for player hosted matches"""

import base64
import hashlib
import hmac
import ipaddress
import json
import os
import secrets
import time
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Attr, Key
from botocore.exceptions import ClientError

TTL_SECONDS = 45
MAX_PLAYERS = 20
PROTOCOL = 1
RTC_PROTOCOL = 2
SIGNAL_SECONDS = 45
ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
table = None


def rooms():
    global table
    if table is None:
        region = os.environ.get("ROOMS_REGION", "").strip() or None
        table = boto3.resource("dynamodb", region_name=region).Table(
            os.environ.get("ROOMS_TABLE", "FlowstateRooms")
        )
    return table


def reply(status, data):
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json", "cache-control": "no-store"},
        "body": json.dumps(data, default=lambda value: int(value) if isinstance(value, Decimal) else str(value)),
    }


def body_of(event, limit=4096):
    raw = event.get("body") or "{}"
    if len(raw) > limit * 2:
        raise ValueError("Request body is too large")
    if event.get("isBase64Encoded"):
        try:
            raw = base64.b64decode(raw, validate=True).decode("utf-8")
        except (ValueError, UnicodeError) as error:
            raise ValueError("Invalid request body") from error
    if len(raw.encode("utf-8")) > limit:
        raise ValueError("Request body is too large")
    try:
        body = json.loads(raw)
    except (ValueError, TypeError) as error:
        raise ValueError("Body must be valid JSON") from error
    if not isinstance(body, dict):
        raise ValueError("Body must be a JSON object")
    return body


def integer(body, key, low, high, default=None):
    value = body.get(key, default)
    if type(value) is not int or not low <= value <= high:
        raise ValueError(f"{key} must be an integer between {low} and {high}")
    return value


def state_of(body, default="lobby"):
    state = body.get("state", default)
    if state not in ("lobby", "in_game"):
        raise ValueError("state must be lobby or in_game")
    return state


def source_ip(event):
    context = event.get("requestContext") or {}
    address = (context.get("http") or {}).get("sourceIp") or (context.get("identity") or {}).get("sourceIp", "")
    try:
        address = ipaddress.ip_address(address)
    except ValueError as error:
        raise ValueError("Could not determine the host IP") from error
    if not address.is_global and os.environ.get("ALLOW_PRIVATE_IP") != "true":
        raise ValueError("Host must have a public IP")
    return str(address)


def clean(item):
    # keep the host token out of room lookups
    return {key: item[key] for key in (
        "room_code", "ip", "port", "players", "max_players", "state", "last_seen", "protocol"
    )}


def bearer(event):
    headers = {key.lower(): value for key, value in (event.get("headers") or {}).items()}
    value = headers.get("authorization", "")
    return value[7:].strip() if value.lower().startswith("bearer ") else ""


def get_room(code):
    item = rooms().get_item(Key={"room_code": code}, ConsistentRead=True).get("Item")
    if not item or int(item["expires_at"]) <= int(time.time()):
        return None
    return item


def register(event, body):
    address = source_ip(event)
    port = integer(body, "port", 1, 65535)
    players = integer(body, "players", 1, MAX_PLAYERS, 1)
    protocol = integer(body, "protocol", PROTOCOL, RTC_PROTOCOL, PROTOCOL)
    state = state_of(body)
    timestamp = int(time.time())
    for _ in range(5):
        code = "".join(secrets.choice(ALPHABET) for _ in range(6))
        item = {
            "room_code": code, "ip": address, "port": port, "players": players,
            "max_players": MAX_PLAYERS, "state": state, "protocol": protocol,
            "host_token": secrets.token_urlsafe(32), "last_seen": timestamp,
            "expires_at": timestamp + TTL_SECONDS,
        }
        if protocol == RTC_PROTOCOL:
            item.update(sessions={}, signal_revision=0)
        try:
            rooms().put_item(Item=item, ConditionExpression="attribute_not_exists(room_code)")
            return reply(201, {**clean(item), "host_token": item["host_token"], "heartbeat_interval_seconds": 10,
                               **({"ice_servers": ice_servers(code)} if protocol == RTC_PROTOCOL else {})})
        except ClientError as error:
            if error.response["Error"]["Code"] != "ConditionalCheckFailedException":
                raise
    return reply(503, {"error": "Could not generate a room code"})


def quick_match(body):
    protocol = integer(body, "protocol", PROTOCOL, RTC_PROTOCOL, PROTOCOL)
    excluded = body.get("exclude_codes", [])
    if not isinstance(excluded, list) or len(excluded) > 10 or not all(isinstance(code, str) for code in excluded):
        raise ValueError("exclude_codes must contain at most 10 codes")
    params = {
        "IndexName": "state-expires-index",
        "KeyConditionExpression": Key("state").eq("lobby") & Key("expires_at").gt(int(time.time())),
        "FilterExpression": Attr("players").lt(MAX_PLAYERS) & Attr("protocol").eq(protocol),
        "Limit": 100,
    }
    # bound directory reads per request
    for _ in range(5):
        result = rooms().query(**params)
        candidates = [item for item in result.get("Items", []) if item["room_code"] not in excluded]
        while candidates:
            candidate = secrets.choice(candidates)
            candidates.remove(candidate)
            item = get_room(candidate["room_code"])
            if item and item["state"] == "lobby" and item["players"] < MAX_PLAYERS and item["protocol"] == protocol:
                return reply(200, clean(item))
        if not result.get("LastEvaluatedKey"):
            return reply(404, {"error": "No joinable matches found"})
        params["ExclusiveStartKey"] = result["LastEvaluatedKey"]
    return reply(503, {"error": "Match search is busy please retry"})


def room_request(event, body, method, parts):
    code = parts[1].upper()
    if len(code) != 6 or any(char not in ALPHABET for char in code):
        return reply(400, {"error": "Room codes contain 6 letters or numbers"})
    item = get_room(code)
    if not item:
        return reply(404, {"error": "Room not found or expired"})
    if method == "GET":
        if item["protocol"] not in (PROTOCOL, RTC_PROTOCOL):
            return reply(409, {"error": "Room uses a different game version"})
        if item["players"] >= MAX_PLAYERS:
            return reply(409, {"error": "Room is full"})
        return reply(200, clean(item))
    token = bearer(event)
    if not secrets.compare_digest(token, item["host_token"]):
        return reply(401, {"error": "Invalid host token"})
    if method == "DELETE":
        rooms().delete_item(
            Key={"room_code": code}, ConditionExpression="host_token=:token",
            ExpressionAttributeValues={":token": token},
        )
        return reply(200, {"ok": True})
    players = integer(body, "players", 1, MAX_PLAYERS, int(item["players"]))
    state = state_of(body, item["state"])
    timestamp = int(time.time())
    rooms().update_item(
        Key={"room_code": code},
        UpdateExpression="SET players=:p, #st=:s, last_seen=:t, expires_at=:e",
        ConditionExpression="host_token=:token AND expires_at>:now",
        ExpressionAttributeNames={"#st": "state"},
        ExpressionAttributeValues={
            ":p": players, ":s": state, ":t": timestamp, ":e": timestamp + TTL_SECONDS,
            ":token": token, ":now": timestamp,
        },
    )
    return reply(200, {"ok": True})


def ice_servers(identity):
    servers = []
    stun = [url.strip() for url in os.environ.get("STUN_URLS", "stun:stun.l.google.com:19302").split(",") if url.strip()]
    if stun:
        servers.append({"urls": stun})
    turn = [url.strip() for url in os.environ.get("TURN_URLS", "").split(",") if url.strip()]
    secret = os.environ.get("TURN_SHARED_SECRET", "")
    if turn and secret:
        username = f"{int(time.time()) + 86400}:{identity}"
        credential = base64.b64encode(hmac.new(secret.encode(), username.encode(), hashlib.sha1).digest()).decode()
        servers.append({"urls": turn, "username": username, "credential": credential})
    return servers


def signal_payload(value, kind):
    if not isinstance(value, dict) or value.get("type") != kind:
        raise ValueError(f"Expected an {kind} description")
    sdp, candidates = value.get("sdp"), value.get("candidates")
    if not isinstance(sdp, str) or not sdp.startswith("v=0") or not isinstance(candidates, list) or len(candidates) > 24:
        raise ValueError("Invalid connection description")
    for candidate in candidates:
        if not isinstance(candidate, dict) or not isinstance(candidate.get("media"), str) or not isinstance(candidate.get("name"), str):
            raise ValueError("Invalid ICE candidate")
        integer(candidate, "index", 0, 16)
    # bound each side so nineteen pending handshakes fit in one dynamodb item
    if len(json.dumps(value).encode()) > 6000:
        raise ValueError("Connection description is too large")
    return {"type": kind, "sdp": sdp, "candidates": candidates}


def signaling(event, body, parts):
    code = parts[1].upper()
    if len(code) != 6 or any(char not in ALPHABET for char in code):
        return reply(400, {"error": "Invalid room code"})
    token = bearer(event)
    for _ in range(5):
        item = get_room(code)
        if not item:
            return reply(404, {"error": "Room not found or expired"})
        if item["protocol"] != RTC_PROTOCOL:
            return reply(409, {"error": "Room does not support WebRTC"})
        timestamp = int(time.time())
        sessions = {key: value for key, value in item["sessions"].items() if value["expires_at"] > timestamp}
        before = json.dumps(sessions, default=int, sort_keys=True)
        status = 200
        if parts[2] == "signals":
            if not secrets.compare_digest(token, item["host_token"]):
                return reply(401, {"error": "Invalid host token"})
            answers, closed = body.get("answers", {}), body.get("closed", [])
            if not isinstance(answers, dict) or len(answers) > 19 or not isinstance(closed, list) or len(closed) > 19:
                raise ValueError("Invalid signal batch")
            if not all(isinstance(key, str) for key in closed):
                raise ValueError("Invalid closed connections")
            for key, answer in answers.items():
                payload = signal_payload(answer, "answer")
                if key in sessions and "offer" in sessions[key]:
                    sessions[key]["answer"] = payload
            for key in closed:
                sessions.pop(key, None)
            offers = {key: value["offer"] for key, value in sessions.items() if "offer" in value and "answer" not in value}
            response = {"offers": offers, "ice_servers": ice_servers(code) if offers else []}
        elif len(parts) == 3:
            # retries with the same random join token reuse the reservation
            if len(token) != 64 or any(char not in "0123456789abcdef" for char in token):
                raise ValueError("A random 64 character join token is required")
            key = next((key for key, value in sessions.items() if secrets.compare_digest(value["token"], token)), None)
            if key is None:
                if item["players"] + len(sessions) >= MAX_PLAYERS:
                    return reply(409, {"error": "Room is full or has pending joins"})
                key = str(secrets.randbelow(2147483645) + 2)
                while key in sessions:
                    key = str(secrets.randbelow(2147483645) + 2)
                sessions[key] = {"token": token, "expires_at": timestamp + SIGNAL_SECONDS}
            status, response = 201, {"peer_id": int(key), "ice_servers": ice_servers(code + key)}
        else:
            key = parts[3]
            session = sessions.get(key)
            if not session:
                return reply(404, {"error": "Connection expired"})
            if not secrets.compare_digest(token, session["token"]):
                return reply(401, {"error": "Invalid connection token"})
            if body.get("cancel") is True:
                sessions.pop(key)
                response = {"ok": True}
            else:
                if "offer" in body:
                    offer = signal_payload(body["offer"], "offer")
                    if "offer" in session and session["offer"] != offer:
                        return reply(409, {"error": "Connection offer cannot change"})
                    session["offer"] = offer
                response = {"answer": session.get("answer")}
        if before == json.dumps(sessions, default=int, sort_keys=True) and len(sessions) == len(item["sessions"]):
            return reply(status, response)
        try:
            rooms().update_item(
                Key={"room_code": code},
                UpdateExpression="SET sessions=:s, signal_revision=:next",
                ConditionExpression="signal_revision=:rev AND host_token=:host AND expires_at>:now AND players=:players",
                ExpressionAttributeValues={":s": sessions, ":next": item["signal_revision"] + 1,
                                           ":rev": item["signal_revision"], ":host": item["host_token"],
                                           ":now": timestamp, ":players": item["players"]},
            )
            return reply(status, response)
        except ClientError as error:
            if error.response["Error"]["Code"] != "ConditionalCheckFailedException":
                raise
    return reply(409, {"error": "Connection busy please retry"})


def handler(event, context):
    method = ((event.get("requestContext") or {}).get("http") or {}).get("method") or event.get("httpMethod", "GET")
    path = (event.get("rawPath") or event.get("path") or "/").strip("/")
    parts = path.split("/")
    try:
        is_signal = parts[0] == "rooms" and (
            (len(parts) == 3 and parts[2] in ("connections", "signals")) or
            (len(parts) == 4 and parts[2] == "connections")
        )
        body = body_of(event, 131072 if is_signal else 4096)
        if method == "POST" and is_signal:
            return signaling(event, body, parts)
        if method == "POST" and path == "rooms":
            return register(event, body)
        if method == "POST" and path == "matchmaking":
            return quick_match(body)
        if parts[0] == "rooms" and (
            (len(parts) == 2 and method in ("GET", "DELETE")) or
            (len(parts) == 3 and parts[2] == "heartbeat" and method == "POST")
        ):
            return room_request(event, body, method, parts)
        return reply(404, {"error": "Not found"})
    except ValueError as error:
        return reply(400, {"error": str(error)})
    except ClientError as error:
        if error.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return reply(409, {"error": "Room changed or expired"})
        print("directory error", str(error))
        return reply(503, {"error": "Matchmaking is temporarily unavailable"})


def lambda_handler(event, context):
    return handler(event, context)

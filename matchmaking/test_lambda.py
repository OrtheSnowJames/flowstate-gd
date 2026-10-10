import base64
import hashlib
import hmac
import json
import os
import unittest
from unittest.mock import patch

import boto3
from botocore.exceptions import ClientError
from moto import mock_aws

from matchmaking import lambda_function as api


def create_table():
    return boto3.resource("dynamodb", region_name="us-east-1").create_table(
        TableName="FlowstateRooms", BillingMode="PAY_PER_REQUEST",
        KeySchema=[{"AttributeName": "room_code", "KeyType": "HASH"}],
        AttributeDefinitions=[
            {"AttributeName": "room_code", "AttributeType": "S"},
            {"AttributeName": "state", "AttributeType": "S"},
            {"AttributeName": "expires_at", "AttributeType": "N"},
        ],
        GlobalSecondaryIndexes=[{
            "IndexName": "state-expires-index",
            "KeySchema": [
                {"AttributeName": "state", "KeyType": "HASH"},
                {"AttributeName": "expires_at", "KeyType": "RANGE"},
            ],
            "Projection": {"ProjectionType": "INCLUDE", "NonKeyAttributes": ["players", "protocol"]},
        }],
    )


def request(method, path, body=None, token="", address="8.8.8.8"):
    event = {
        "rawPath": path,
        "requestContext": {"http": {"method": method, "sourceIp": address}},
        "headers": {"Authorization": "Bearer " + token},
        "body": json.dumps(body or {}),
    }
    result = api.handler(event, None)
    return result["statusCode"], json.loads(result["body"])


@mock_aws
class MatchmakingTests(unittest.TestCase):
    def setUp(self):
        api.table = create_table()

    def test_default_lambda_entry_point(self):
        event = {"httpMethod": "POST", "path": "/matchmaking", "body": "{}"}
        self.assertEqual(api.lambda_handler(event, None), api.handler(event, None))
        self.assertEqual(api.lambda_handler(event, None)["statusCode"], 404)

    def test_permission_error_details_stay_in_logs(self):
        error = ClientError({"Error": {
            "Code": "AccessDeniedException",
            "Message": "Test role cannot perform dynamodb:PutItem on the test table",
        }}, "PutItem")
        with patch.object(api.table, "put_item", side_effect=error), patch("builtins.print") as log:
            status, body = request("POST", "/rooms", {"port": 7654}, token="private-test-token")
        self.assertEqual(status, 503)
        self.assertEqual(body, {"error": "Matchmaking is temporarily unavailable"})
        log.assert_called_once_with("directory error", str(error))
        self.assertNotIn("private-test-token", str(log.call_args))

    def test_table_region_overrides_lambda_region(self):
        api.table = None
        with patch.dict(os.environ, {
            "AWS_DEFAULT_REGION": "us-east-2", "ROOMS_REGION": " us-east-1 ",
            "ROOMS_TABLE": "FlowstateRooms",
        }):
            room = self.register()
            self.assertEqual(api.rooms().meta.client.meta.region_name, "us-east-1")
            self.assertEqual(request("GET", "/rooms/" + room["room_code"])[0], 200)
            self.assertEqual(request("POST", "/matchmaking")[0], 200)

    def test_blank_table_region_uses_default_region(self):
        api.table = None
        with patch.dict(os.environ, {
            "AWS_DEFAULT_REGION": "us-east-1", "ROOMS_REGION": " ",
            "ROOMS_TABLE": "FlowstateRooms",
        }):
            self.register()
            self.assertEqual(api.rooms().meta.client.meta.region_name, "us-east-1")

    def register(self, **kwargs):
        status, room = request("POST", "/rooms", {"port": 7654, **kwargs})
        self.assertEqual(status, 201, room)
        return room

    def test_lifecycle_and_token_privacy(self):
        room = self.register(ip="1.1.1.1")
        self.assertEqual(room["ip"], "8.8.8.8")
        code, token = room["room_code"], room["host_token"]
        status, public = request("GET", "/rooms/" + code.lower())
        self.assertEqual(status, 200)
        self.assertNotIn("host_token", public)
        self.assertEqual(request("POST", f"/rooms/{code}/heartbeat", token="wrong")[0], 401)
        self.assertEqual(request("DELETE", f"/rooms/{code}", token="wrong")[0], 401)
        self.assertEqual(request("POST", f"/rooms/{code}/heartbeat", {"players": 7}, token)[0], 200)
        self.assertEqual(request("GET", "/rooms/" + code)[1]["players"], 7)
        self.assertEqual(request("DELETE", "/rooms/" + code, token=token)[0], 200)
        self.assertEqual(request("GET", "/rooms/" + code)[0], 404)

    def test_random_matches_exclude_full_started_and_expired(self):
        self.register(players=20)
        started = self.register(state="in_game")
        expired = self.register()
        api.table.update_item(Key={"room_code": expired["room_code"]},
                              UpdateExpression="SET expires_at=:t", ExpressionAttributeValues={":t": 1})
        self.assertEqual(request("POST", "/matchmaking")[0], 404)
        self.assertEqual(request("GET", "/rooms/" + started["room_code"])[0], 200)
        available = [self.register(), self.register()]
        codes = {room["room_code"] for room in available}
        for choose in [lambda items: items[0], lambda items: items[-1]]:
            with patch.object(api.secrets, "choice", side_effect=choose):
                status, result = request("POST", "/matchmaking")
                self.assertEqual(status, 200)
                self.assertIn(result["room_code"], codes)
                self.assertNotIn("host_token", result)
        self.assertEqual(request("POST", "/matchmaking", {"exclude_codes": list(codes)})[0], 404)

    def test_expiry_does_not_wait_for_dynamodb_ttl(self):
        room = self.register()
        with patch.object(api.time, "time", return_value=room["last_seen"] + api.TTL_SECONDS):
            self.assertEqual(request("GET", "/rooms/" + room["room_code"])[0], 404)
            self.assertEqual(request("POST", f'/rooms/{room["room_code"]}/heartbeat', token=room["host_token"])[0], 404)

    def test_validation(self):
        for body in [{"port": 0}, {"port": 65536}, {"port": True}, {"port": 7.5},
                     {"port": 7654, "players": 21}, {"port": 7654, "players": 0},
                     {"port": 7654, "protocol": 3}, {"port": 7654, "state": "bad"}]:
            self.assertEqual(request("POST", "/rooms", body)[0], 400)
        with patch.dict(os.environ, {"ALLOW_PRIVATE_IP": "false"}):
            self.assertEqual(request("POST", "/rooms", {"port": 7654}, address="127.0.0.1")[0], 400)
        for body in ["[]", "null", "true", "{", "x" * 5000]:
            self.assertEqual(api.handler({"body": body}, None)["statusCode"], 400)
        event = {"body": base64.b64encode(b"{}").decode(), "isBase64Encoded": True}
        self.assertEqual(api.body_of(event), {})

    def test_full_and_state_changes(self):
        room = self.register()
        code, token = room["room_code"], room["host_token"]
        self.assertEqual(request("POST", f"/rooms/{code}/heartbeat", {"players": 21}, token)[0], 400)
        request("POST", f"/rooms/{code}/heartbeat", {"players": 20}, token)
        self.assertEqual(request("GET", "/rooms/" + code)[0], 409)
        self.assertEqual(request("POST", "/matchmaking")[0], 404)
        request("POST", f"/rooms/{code}/heartbeat", {"players": 2, "state": "in_game"}, token)
        self.assertEqual(request("POST", "/matchmaking")[0], 404)
        request("POST", f"/rooms/{code}/heartbeat", {"state": "lobby"}, token)
        self.assertEqual(request("POST", "/matchmaking")[0], 200)

    def rtc_room(self):
        room = self.register(protocol=2)
        return room, "/rooms/" + room["room_code"]

    def reserve(self, path, token="a" * 64):
        status, session = request("POST", path + "/connections", token=token)
        self.assertEqual(status, 201, session)
        return session, path + "/connections/" + str(session["peer_id"])

    def description(self, kind):
        return {"type": kind, "sdp": "v=0\r\ntest", "candidates": [
            {"media": "0", "index": 0, "name": "candidate:test"},
        ]}

    def test_webrtc_signaling_lifecycle_and_privacy(self):
        room, path = self.rtc_room()
        session, client_path = self.reserve(path)
        self.assertEqual(self.reserve(path)[0]["peer_id"], session["peer_id"])
        other, other_path = self.reserve(path, "b" * 64)
        offer, answer = self.description("offer"), self.description("answer")
        self.assertEqual(request("POST", client_path, {"offer": offer}, "a" * 64), (200, {"answer": None}))
        self.assertEqual(request("POST", client_path, token="b" * 64)[0], 401)
        self.assertEqual(request("POST", path + "/signals", token="a" * 64)[0], 401)
        status, signals = request("POST", path + "/signals", token=room["host_token"])
        self.assertEqual(status, 200)
        self.assertEqual(signals["offers"], {str(session["peer_id"]): offer})
        self.assertNotIn("a" * 64, json.dumps(signals))
        self.assertNotIn("sessions", request("GET", path)[1])
        self.assertEqual(request("POST", other_path, token="b" * 64), (200, {"answer": None}))
        request("POST", path + "/signals", {"answers": {str(session["peer_id"]): answer}}, room["host_token"])
        self.assertEqual(request("POST", client_path, token="a" * 64), (200, {"answer": answer}))
        self.assertEqual(request("POST", path + "/signals", token=room["host_token"])[1]["offers"], {})
        request("POST", path + "/signals", {"closed": [str(session["peer_id"])]}, room["host_token"])
        self.assertEqual(request("POST", client_path, token="a" * 64)[0], 404)
        request("POST", other_path, {"cancel": True}, "b" * 64)
        self.assertEqual(api.get_room(room["room_code"])["sessions"], {})

    def test_webrtc_capacity_and_expiry(self):
        room, path = self.rtc_room()
        for index in range(19):
            self.reserve(path, f"{index:064x}")
        self.assertEqual(request("POST", path + "/connections", token="f" * 64)[0], 409)
        # expired reservations release slots before dynamodb cleanup
        with patch.object(api.time, "time", return_value=room["last_seen"] + 30):
            request("POST", path + "/heartbeat", token=room["host_token"])
        with patch.object(api.time, "time", return_value=room["last_seen"] + 46):
            self.reserve(path, "f" * 64)
            self.assertEqual(len(api.get_room(room["room_code"])["sessions"]), 1)
        request("DELETE", path, token=room["host_token"])
        self.assertEqual(request("POST", path + "/signals", token=room["host_token"])[0], 404)

    def test_webrtc_protocols_do_not_mix(self):
        room, path = self.rtc_room()
        self.assertEqual(request("POST", "/matchmaking", {"protocol": 1})[0], 404)
        self.assertEqual(request("POST", "/matchmaking", {"protocol": 2})[1]["room_code"], room["room_code"])
        direct = self.register()
        self.assertEqual(request("POST", f'/rooms/{direct["room_code"]}/connections', token="a" * 64)[0], 409)
        request("POST", path + "/heartbeat", {"state": "in_game"}, room["host_token"])
        self.assertEqual(request("POST", "/matchmaking", {"protocol": 2})[0], 404)
        self.reserve(path)

    def test_webrtc_validation_and_immutable_offer(self):
        room, path = self.rtc_room()
        self.assertEqual(request("POST", path + "/connections")[0], 400)
        _, client_path = self.reserve(path)
        for offer in [None, {}, self.description("answer"), {**self.description("offer"), "sdp": "v=0" + "x" * 6000}]:
            self.assertEqual(request("POST", client_path, {"offer": offer}, "a" * 64)[0], 400)
        offer = self.description("offer")
        request("POST", client_path, {"offer": offer}, "a" * 64)
        offer["sdp"] += "changed"
        self.assertEqual(request("POST", client_path, {"offer": offer}, "a" * 64)[0], 409)
        for batch in [{"answers": []}, {"closed": [{}]}, {"answers": {"2": {}}}]:
            self.assertEqual(request("POST", path + "/signals", batch, room["host_token"])[0], 400)

    def test_webrtc_conditional_conflict_retries(self):
        _, path = self.rtc_room()
        original = api.table.update_item
        error = ClientError({"Error": {"Code": "ConditionalCheckFailedException"}}, "UpdateItem")
        def competing_write(**kwargs):
            if update.call_count == 1:
                raise error
            return original(**kwargs)

        with patch.object(api.table, "update_item", side_effect=competing_write) as update:
            self.reserve(path)
            self.assertEqual(update.call_count, 2)

    def test_turn_credentials_never_expose_shared_secret(self):
        with patch.dict(os.environ, {"TURN_URLS": "turn:relay.example.com:3478", "TURN_SHARED_SECRET": "test-secret"}):
            room, path = self.rtc_room()
            session, _ = self.reserve(path)
        for value in (room, session):
            turn = value["ice_servers"][-1]
            expected = base64.b64encode(hmac.new(b"test-secret", turn["username"].encode(), hashlib.sha1).digest()).decode()
            self.assertEqual(turn["credential"], expected)
            self.assertNotIn("test-secret", json.dumps(value))
        public = request("GET", path)[1]
        self.assertNotIn("ice_servers", public)


if __name__ == "__main__":
    unittest.main()

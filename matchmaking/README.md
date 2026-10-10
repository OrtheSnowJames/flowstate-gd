# Player-hosted matchmaking

Each room has at most 20 connections, including the host and spectators. The host runs the match. Lambda handles discovery and WebRTC signaling, never game simulation or gameplay packets.

## In the game

- Play > Quick Play joins a random WebRTC lobby or hosts one when none are available.
- Play > Join Code resolves a six-character room code. In-progress matches use the existing spectate prompt.
- Custom Server > Host keeps direct-IP ENet networking and publishes a code when matchmaking is configured. These rooms are not selected by WebRTC Quick Play.
- The lobby shows the room code. Click it to copy.
- Hosts publish occupancy and round state, heartbeat every 10 seconds, and remove the room when leaving. Crashes expire after 45 seconds.
- Solo Play and Connect to Localhost do not publish rooms.
- The existing online penalty also blocks matchmaking.

## Deployment

No AWS resources are created by editing or testing these files. Deploying the template creates billable AWS resources.

With the AWS SAM CLI installed and your AWS credentials configured, run from this directory:

```sh
sam build --template-file template.yaml
sam deploy --guided
```

The template creates an on-demand DynamoDB table with TTL and a `state-expires-index`, an ARM Lambda, a public Function URL, and logs retained for 7 days. It grants the Lambda only the table operations it uses. It also includes both permissions required for public Function URL invocation.

Put the stack's `MatchmakingUrl` output in `connect_to_url.txt` at the project root. The game reads this file at startup and trims whitespace and the trailing slash.

When creating an export preset, include `connect_to_url.txt` in its non-resource export filter so packaged builds can read it too. There are no export presets in this project yet.

Alternatively, configure a fallback in `project.godot`:

```ini
[matchmaking]
endpoint="https://YOUR_FUNCTION_URL.lambda-url.YOUR_REGION.on.aws"
```

For local development, `FLOWSTATE_MATCHMAKING_URL` overrides both the text file and project setting. Priority is environment variable, text file, then project setting. Only HTTPS and localhost HTTP endpoints are accepted. No AWS credentials belong in the game.

For an existing table, add the index before uploading this version of `lambda_function.py`. The index uses `state` (String) as its partition key and `expires_at` (Number) as its sort key, projecting `players` and `protocol`. Set Lambda's handler to `lambda_function.handler` and environment variable `ROOMS_TABLE` to your table name.

If the table is in a different region from Lambda, set the Lambda environment variable `ROOMS_REGION` to the table's region. For example, a table in N. Virginia uses `ROOMS_REGION=us-east-1`, even if Lambda is in Ohio. Without this setting, the SDK uses its default region. The DynamoDB resource ARNs in the execution-role policy must also use the table's region; leave the Lambda Function URL policy unchanged. Redeploy the updated Python file before using this setting. See [Boto3 region configuration](https://docs.aws.amazon.com/boto3/latest/reference/core/session.html).

## Host networking

Quick Play uses WebRTC with ICE/STUN to find a direct route, including between clients on the same LAN. It does not listen on the fixed custom server port or modify router settings. A configured TURN relay is the fallback when a direct connection is not possible. A relay forwards packets; the player host still runs the match. Without TURN, some routers and CGNAT combinations will still prevent joining.

The desktop WebRTC dependency is included in `addons/webrtc_native`, from the official Godot `1.2.2-stable` release for Godot 4.3+. Restart an already-open editor so it discovers the extension. Keep the extension and its licenses in exported builds. The downloaded archive's SHA256 is `98e9446921740d995bd9ca1be48798dc3c2ceed51e044a25ce18b3cff11f56e5`.

Custom Server and Connect to Localhost still use ENet. External direct-IP connections still require a forwarded inbound UDP port, normally 7654. The directory derives that public IP from AWS's request context. WebRTC does not make the custom IP path traverse NAT. If the host quits, either kind of match ends and clients return to the menu.

## Updating your existing Lambda

Replace the deployed code with the updated `lambda_function.py` and click Deploy. Keep handler `lambda_function.lambda_handler` or `lambda_function.handler`. No new table, index, or IAM permissions are required. Keep your existing `ROOMS_TABLE=FlowstateRooms` and `ROOMS_REGION=us-east-1` settings.

Until the updated Lambda is deployed, Quick Play will reject protocol 2. Both players need this updated game build. The updated service continues accepting protocol 1 for direct-IP rooms and the existing curl tests.

## TURN setup

Use a TURN service that supports coturn-style shared-secret credentials, or run coturn on a public server. Lambda cannot host the TURN relay. Nothing here purchases or deploys a relay automatically.

In Lambda > Configuration > Environment variables, add:

| Variable | Value |
| --- | --- |
| `TURN_URLS` | Your provider's comma-separated TURN URLs, such as `turn:relay.example.com:3478` |
| `TURN_SHARED_SECRET` | The shared authentication secret configured on that relay |
| `STUN_URLS` | Optional comma-separated STUN URLs; defaults to `stun:stun.l.google.com:19302` |

Do not put the shared secret in the game, repository, or `connect_to_url.txt`. Lambda generates expiring HMAC credentials for each connection. Credentials last 24 hours; connections beyond that lifetime are not guaranteed. A provider API key or static TURN password is not the shared secret and needs a provider-specific integration instead.

For a self-hosted relay, enable coturn `use-auth-secret`, configure `static-auth-secret` to match Lambda, and set a realm. Expose its configured listener and UDP relay port range on the server firewall. Deny relay access to loopback, private and link-local destinations; disable administrative interfaces you do not use; set allocation, bandwidth and user quotas. Add TLS with a valid certificate if your chosen client/relay transport supports it. Consult the [coturn configuration reference](https://github.com/coturn/coturn/blob/master/README.turnserver) for the server's deployment environment.

Configure spending/usage limits and player authentication before public release. The current playtest endpoint has no player login, so anyone who can register a room can obtain temporary relay credentials. Expiring credentials alone do not prevent relay abuse. No relay can guarantee connectivity on every network; test your provider with the native desktop builds and restrictive networks you support.

Test Quick Play on two different internet connections after deployment. A same-machine success verifies signaling and replication, not external NAT traversal or the relay fallback.

## API

All requests use JSON. Registration and matchmaking use `protocol: 2` for WebRTC or `protocol: 1` for ENet.

| Request | Purpose |
| --- | --- |
| POST /rooms | Register with `port`, `players`, `state`, and `protocol`; returns room code and private host token |
| POST /rooms/CODE/heartbeat | Update `players` and `state`; requires `Authorization: Bearer HOST_TOKEN` |
| GET /rooms/CODE | Resolve an unexpired, non-full room; can return an in-progress match |
| POST /matchmaking | Random available lobby for `protocol`; optionally omit up to 10 `exclude_codes` |
| DELETE /rooms/CODE | Remove the room; requires the host token |
| POST /rooms/CODE/connections | Reserve a WebRTC peer ID; bearer is a client-generated random 32-byte hex token; returns ICE settings |
| POST /rooms/CODE/connections/ID | Submit an `offer`, poll for an `answer`, or send `cancel: true`; requires that connection's token |
| POST /rooms/CODE/signals | Host-only exchange of pending offers, `answers` keyed by peer ID, and `closed` peer ID strings |

State is `lobby` or `in_game`. Room lookup never exposes host tokens. Expiry is checked during lookup because DynamoDB TTL deletion is asynchronous. Quick Play queries an index and rechecks the chosen room with a consistent table read.

WebRTC reservations expire after 45 seconds and count toward the 20-player capacity. The host also limits actual connections to 19 remote peers. Signaling is stored in the room item with conditional revisions to avoid overwriting simultaneous joins. Offers and answers contain the SDP and gathered ICE candidates, bounded to 6000 bytes each. Successful connections remove their signaling records; game packets then travel directly or through TURN. Clients stop polling once they receive the answer. The host checks for new joins every two seconds, including during a match for spectators.

## HTTP request tests

Run `bash matchmaking/test_requests.sh` from the repository root. It reads `connect_to_url.txt`, or accepts an explicit URL:

```sh
bash matchmaking/test_requests.sh https://YOUR_FUNCTION_URL.lambda-url.YOUR_REGION.on.aws
bash matchmaking/test_requests.sh http://127.0.0.1:18765
```

Requires `curl` and `jq`. The script prints responses with the host token removed, checks HTTP statuses and response fields, and exits nonzero on failure. It tests validation, registration, lookup, token protection, heartbeats, matchmaking, full rooms, and deletion. The temporary room stays in-game so Quick Play never selects it. Cleanup runs on exit or interruption; a lost registration response or forced kill can leave it until the 45-second expiry. Running against AWS makes real requests and temporary DynamoDB writes.

## Local tests

From the repository root:

```sh
python3 -m venv /tmp/flowstate-matchmaking-venv
/tmp/flowstate-matchmaking-venv/bin/pip install -r matchmaking/requirements-dev.txt
/tmp/flowstate-matchmaking-venv/bin/python -m unittest matchmaking.test_lambda -v
PYTHON_BIN=/tmp/flowstate-matchmaking-venv/bin/python bash tests/run_matchmaking.sh
bash tests/run_webrtc_replication.sh
```

The matchmaking test launches a local HTTP adapter, mocked DynamoDB, and three Godot instances using real WebRTC connections. The WebRTC replication test runs the existing four-client gameplay suite over the new transport, including late spectators, movement, attacks, fainting, drones and scoreboards. Set `GODOT_BIN` and `PYTHON_BIN` for other installations. Port 18765 must be available; run these suites separately. `bash tests/run_match_replication.sh` still tests ENet on port 17654.

Run the adapter separately to test manually:

```sh
/tmp/flowstate-matchmaking-venv/bin/python -m matchmaking.local_server
```

Launch Godot with `FLOWSTATE_MATCHMAKING_URL=http://127.0.0.1:18765`. The adapter binds only to localhost, keeps no durable rooms, and never calls AWS. Its private-IP allowance is for local tests only.

Godot regression scenes: `tests/matchmaking.tscn` checks UI and penalties; `tests/room_capacity.tscn` checks the real host-plus-19 ENet limit.

## Cost and security limits

There is no dedicated simulation server. TURN providers charge for relayed traffic or server resources. Each WebRTC host generates about 30 signaling polls and six heartbeats per minute, plus join signaling, index writes, occupancy changes, registration, lookups, and logs. Idle signaling polls read but do not write the room. This is not free or a hard spending cap.

The template caps Lambda concurrency at five and each match search examines at most five index pages of 100 entries. This bounds an individual search, not total spend. Set AWS Budgets alerts and monitor usage before sharing the endpoint.

This is a small-playtest service, not an abuse-resistant public launch service. The Function URL is unauthenticated: anyone can register rooms or issue lookups. Room tokens protect updates/deletion, but do not authenticate players or prove hosts are reachable. Add player authentication, registration quotas and request rate limiting before public release. Do not embed a shared secret in the client as a substitute.

ENet joins do not reserve slots, but ENet enforces the 20-connection limit. WebRTC reserves pending slots and also checks capacity at the host. A failed connection times out and releases its reservation, or the reservation expires if the client crashes. Penalties remain locally stored, as before, and are not a tamper-proof global ban. There is no automatic host migration or external reachability probe.

## References

- [Godot WebRTC server and client transport](https://docs.godotengine.org/en/stable/classes/class_webrtcmultiplayerpeer.html)
- [Official native WebRTC release](https://github.com/godotengine/webrtc-native/releases/tag/1.2.2-stable)
- [Godot ENet networking and UDP ports](https://docs.godotengine.org/en/stable/classes/class_enetmultiplayerpeer.html)
- [Lambda Function URL request context](https://docs.aws.amazon.com/lambda/latest/dg/urls-invocation.html)
- [Function URL access permissions](https://docs.aws.amazon.com/lambda/latest/dg/urls-auth.html)
- [DynamoDB expired items](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/ttl-expired-items.html)

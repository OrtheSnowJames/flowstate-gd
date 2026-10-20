# Flowstate matchmaking

The matchmaking server handles room codes, Quick Play, room capacity, and WebRTC signaling. Lambda and DynamoDB run the service; a player hosts each match and runs the game simulation.

## Joining and hosting

- Rooms hold 20 connections, including the host and spectators.
- Quick Play joins an available WebRTC lobby or creates one.
- Join Code uses a six-character code. Players can spectate matches already in progress.
- Custom Server uses direct-IP ENet and publishes a room code when matchmaking is configured.
- Standalone Quest can join and spectate but cannot host.
- Hosts update room status every 10 seconds. Abandoned rooms expire after 45 seconds.
- When the host leaves, the match ends. Solo and localhost games stay out of matchmaking.

## Setup

For the existing deployment, upload `lambda_function.py` to Lambda and click **Deploy**. Either handler name works:

- `lambda_function.lambda_handler`
- `lambda_function.handler`

Set these Lambda environment variables:

| Variable | Value |
| --- | --- |
| `ROOMS_TABLE` | `FlowstateRooms`, or your table name |
| `ROOMS_REGION` | Your table's region, currently `us-east-1` |

The table uses `room_code` (String) as its partition key and `expires_at` for TTL. Its `state-expires-index` uses `state` (String) and `expires_at` (Number), projecting `players` and `protocol`.

Lambda's execution role needs `GetItem`, `PutItem`, `UpdateItem`, and `DeleteItem` on the table, plus `Query` on the index. These are DynamoDB permissions on the role, not the Function URL policy.

Put the Function URL in `connect_to_url.txt` at the project root. Keep that file in each export preset's include filter so exported games can connect. Never put AWS credentials in the game.

For a new deployment, run these commands from `matchmaking/` with AWS SAM and credentials configured:

```sh
sam build --template-file template.yaml
sam deploy --guided
```

The template creates the table, index, Lambda, public Function URL, permissions, and logs. Use its `MatchmakingUrl` output in `connect_to_url.txt`. Deploying creates billable AWS resources.

## Connections

Quick Play uses WebRTC to connect players directly without manual port forwarding where the network allows it. TURN provides a relay when a direct connection fails; the player host still runs the match.

To enable TURN, configure a relay separately and set these Lambda variables:

| Variable | Value |
| --- | --- |
| `TURN_URLS` | Comma-separated TURN URLs |
| `TURN_SHARED_SECRET` | The relay's coturn-compatible shared secret |
| `STUN_URLS` | Optional STUN URLs; defaults to Google's STUN server |

Keep the shared secret on the server. Lambda generates temporary relay credentials. Lambda itself does not run the relay.

Custom Server connections over the internet require UDP port forwarding, normally port 7654. Localhost does not. Test Quick Play across two different internet connections to check real network connectivity.

## Tests

From the project root, test the deployed service:

```sh
bash matchmaking/test_requests.sh
```

This requires `curl` and `jq`, reads `connect_to_url.txt`, and creates a temporary test room. You can pass a different URL as the first argument.

For local tests without AWS:

```sh
python3 -m venv /tmp/flowstate-matchmaking-venv
/tmp/flowstate-matchmaking-venv/bin/pip install -r matchmaking/requirements-dev.txt
/tmp/flowstate-matchmaking-venv/bin/python -m unittest matchmaking.test_lambda -v
PYTHON_BIN=/tmp/flowstate-matchmaking-venv/bin/python bash tests/run_matchmaking.sh
bash tests/run_webrtc_replication.sh
```

Run the suites separately. Set `GODOT_BIN` if Godot is installed elsewhere. For manual local testing, run `python -m matchmaking.local_server` in the test environment and launch Godot with `FLOWSTATE_MATCHMAKING_URL=http://127.0.0.1:18765`.

The URL override takes priority over `connect_to_url.txt`, followed by the `matchmaking/endpoint` project setting.

## Operations

The service checks room expiry and capacity, protects host actions with tokens, and handles simultaneous WebRTC joins with reserved slots and conditional updates.

The public endpoint does not authenticate players. Before public release, add player authentication, registration quotas, request rate limits, and AWS budget alerts. Monitor relay usage too. Disconnect penalties are stored locally, and matches do not migrate to another host.

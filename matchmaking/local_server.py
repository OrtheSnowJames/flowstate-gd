"""local lambda adapter with disposable mocked dynamodb"""

import os
from http.server import BaseHTTPRequestHandler, HTTPServer

from moto import mock_aws

from matchmaking import lambda_function as api
from matchmaking.test_lambda import create_table


class Handler(BaseHTTPRequestHandler):
    def handle_request(self):
        length = int(self.headers.get("Content-Length", 0))
        if length > 131072:
            self.send_error(413)
            return
        event = {
            "rawPath": self.path,
            "requestContext": {"http": {"method": self.command, "sourceIp": self.client_address[0]}},
            "headers": dict(self.headers), "body": self.rfile.read(length).decode(),
        }
        result = api.handler(event, None)
        self.send_response(result["statusCode"])
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(result["body"].encode())))
        self.end_headers()
        self.wfile.write(result["body"].encode())

    do_GET = handle_request
    do_POST = handle_request
    do_DELETE = handle_request


if __name__ == "__main__":
    os.environ["ALLOW_PRIVATE_IP"] = "true"
    with mock_aws():
        api.table = create_table()
        server = HTTPServer(("127.0.0.1", 18765), Handler)
        print("local matchmaking at http://127.0.0.1:18765", flush=True)
        server.serve_forever()

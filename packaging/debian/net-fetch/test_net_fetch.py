"""Linux integration tests with a local TLS server, a test CA and Unix datagrams."""

import contextlib
import hashlib
import http.server
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock
from urllib.parse import urlsplit

path = Path(__file__).with_name("cyberdeck-net-fetch")
spec = importlib.util.spec_from_loader("client", importlib.machinery.SourceFileLoader("client", str(path)))
client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(client)


@unittest.skipUnless(sys.platform.startswith("linux"), "requires Linux SO_BINDTODEVICE and AF_UNIX")
class FetchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        tmp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(tmp.cleanup)
        cls.tmp = Path(tmp.name)
        cert, key = cls.tmp / "cert", cls.tmp / "key"
        subprocess.run(["openssl", "req", "-x509", "-nodes", "-newkey", "rsa:2048", "-days", "1",
                        "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost",
                        "-keyout", str(key), "-out", str(cert)], check=True, capture_output=True)
        cls.cert = str(cert)

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                body = bytes(range(192)) if self.path == "/result" else b"x" * 193
                self.send_response(418 if self.path == "/result" else 200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        cls.port = server.server_address[1]
        threading.Thread(target=server.serve_forever, daemon=True).start()
        cls.addClassCleanup(server.server_close)
        cls.addClassCleanup(server.shutdown)

    def test_bound_https_error_body_and_busy_transport_retry(self):
        path = str(self.tmp / "radio.sock")
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as radio:
            radio.bind(path)
            radio.settimeout(3)
            packets = []

            def acknowledge():
                for status in ("ERROR {} busy", "DELIVERED {}"):
                    packet, peer = radio.recvfrom(256)
                    packets.append(packet)
                    request_id = struct.unpack_from("!I", packet)[0]
                    radio.sendto(status.format(request_id).encode(), peer)

            listener = threading.Thread(target=acknowledge, daemon=True)
            listener.start()
            output = io.StringIO()
            argv = [str(client.__file__), f"https://localhost:{self.port}/result", "--interface", "lo",
                    "--timeout", "5"]
            old_handler = signal.getsignal(signal.SIGALRM)
            self.addCleanup(signal.signal, signal.SIGALRM, old_handler)
            with (mock.patch.dict(os.environ, SSL_CERT_FILE=self.cert),
                  mock.patch.object(client, "RESULT_SOCKET", path),
                  mock.patch.object(sys, "argv", argv), contextlib.redirect_stdout(output)):
                client.main()
            listener.join(3)
        events = {row["event"]: row for row in map(json.loads, output.getvalue().splitlines())}
        request_id = events["transport_ack"]["request_id"]
        packet = struct.pack("!IH", request_id, 418) + bytes(range(192))
        self.assertEqual(packets, [packet, packet])
        self.assertEqual(events["tcp"]["local"], "127.0.0.1")
        self.assertEqual(events["https_reply"]["sha256"], hashlib.sha256(packet[6:]).hexdigest())
        self.assertEqual(events["https_reply"]["request_id"], request_id)
        self.assertIn("icmp", events)

    def test_tls_hostname_and_body_limit(self):
        with mock.patch.dict(os.environ, SSL_CERT_FILE=self.cert), contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(ssl.SSLCertVerificationError):
                client.fetch(urlsplit(f"https://127.0.0.1:{self.port}/result"), "lo", 2)
            with self.assertRaisesRegex(ValueError, "exceeds 192"):
                client.fetch(urlsplit(f"https://localhost:{self.port}/oversize"), "lo", 2)

    def test_missing_receiver_times_out(self):
        with mock.patch.object(client, "RESULT_SOCKET", str(self.tmp / "absent")):
            with self.assertRaises(TimeoutError):
                client.deliver(5, 200, b"", time.monotonic() + 0.1)


if __name__ == "__main__":
    unittest.main()

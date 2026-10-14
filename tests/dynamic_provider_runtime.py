#!/usr/bin/env python3
"""Exercise real proxy traffic while updating one running sing-box process."""
import argparse
import base64
import hashlib
import http.server
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class Proxy(http.server.BaseHTTPRequestHandler):
    def do_CONNECT(self):
        credentials = base64.b64encode(("test:" + self.server.password).encode()).decode()
        if self.headers.get("Proxy-Authorization") != "Basic " + credentials:
            self.send_response(407)
            self.end_headers()
            return
        self.send_response(200, "Connection established")
        self.end_headers()
        request_line = self.rfile.readline()
        while self.rfile.readline() not in (b"\r\n", b"\n", b""):
            pass
        body = self.server.label.encode()
        if b"/stream" in request_line:
            self.server.stream_started.set()
            if not self.server.stream_release.wait(5):
                return
        self.wfile.write(b"HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body)
        self.close_connection = True

    def do_GET(self):
        credentials = base64.b64encode(("test:" + self.server.password).encode()).decode()
        if self.headers.get("Proxy-Authorization") != "Basic " + credentials:
            self.send_response(407)
            self.end_headers()
            return
        body = self.server.label.encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True)
    parser.add_argument("--evidence")
    parser.add_argument("--runner", help="Optional emulator, e.g. qemu-aarch64")
    args = parser.parse_args()
    binary = str(Path(args.binary).resolve())
    with tempfile.TemporaryDirectory(prefix="anticheburnet-provider-") as directory:
        work = Path(directory)
        servers = []
        for label in ("A", "B"):
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Proxy)
            server.password, server.label = "old", label
            server.stream_started, server.stream_release = threading.Event(), threading.Event()
            threading.Thread(target=server.serve_forever, daemon=True).start()
            servers.append(server)
        api_port, mixed_port = free_port(), free_port()
        path = work / "providers.json"

        def node(tag="node-a", target=0, password="old"):
            return {"type": "http", "tag": tag, "server": "127.0.0.1", "server_port": servers[target].server_port, "username": "test", "password": password}

        def payload(nodes, members=None):
            return {"outbounds": nodes + [{"type": "selector", "tag": "proxy-main", "outbounds": members or [item["tag"] for item in nodes], "default": "node-a"}], "configuration": {"route": {"final": "proxy-main"}}}

        def write(value):
            temporary = path.with_suffix(".tmp")
            temporary.write_text(json.dumps(value), encoding="utf-8")
            temporary.replace(path)

        write(payload([node()]))
        config = {"log": {"level": "error"}, "inbounds": [{"type": "http", "listen": "127.0.0.1", "listen_port": mixed_port}], "providers": [{"type": "anticheburnet", "tag": "anticheburnet-subscriptions", "path": str(path)}], "route": {"final": "proxy-main"}, "experimental": {"clash_api": {"external_controller": f"127.0.0.1:{api_port}", "secret": "local-provider-test"}, "cache_file": {"enabled": True, "path": str(work / "cache.db")}}}
        config_path = work / "config.json"
        config_path.write_text(json.dumps(config), encoding="utf-8")
        base = f"http://127.0.0.1:{api_port}"
        direct = urllib.request.build_opener(urllib.request.ProxyHandler({}))

        def api(endpoint, method="GET", value=None):
            request = urllib.request.Request(base + endpoint, data=json.dumps(value).encode() if value is not None else None, method=method, headers={"Authorization": "Bearer local-provider-test", "Content-Type": "application/json"})
            with direct.open(request, timeout=5) as response:
                data = response.read()
                return json.loads(data) if data else None

        def traffic(endpoint="probe"):
            # A literal HTTP request avoids environment proxy/no_proxy settings.
            with socket.create_connection(("127.0.0.1", mixed_port), timeout=3) as sock:
                sock.sendall(f"GET http://runtime.test/{endpoint} HTTP/1.1\r\nHost: runtime.test\r\nConnection: close\r\n\r\n".encode())
                chunks = []
                while True:
                    try:
                        chunk = sock.recv(8192)
                    except ConnectionResetError:
                        if not chunks:
                            raise
                        break
                    if not chunk:
                        break
                    chunks.append(chunk)
            response = b"".join(chunks)
            assert response.startswith(b"HTTP/1.1 200"), response[:160]
            return response.split(b"\r\n\r\n", 1)[1].decode()

        samples, failures, timings = [], [], []
        stop = threading.Event()

        def monitor():
            while not stop.wait(0.01):
                try:
                    api("/version")
                    samples.append(time.monotonic())
                except Exception as error:
                    failures.append(str(error))

        with (work / "runtime.log").open("w", encoding="utf-8") as log:
            command = ([args.runner] if args.runner else []) + [binary, "run", "-c", str(config_path)]
            process = subprocess.Popen(command, stdout=log, stderr=log, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
            try:
                for _ in range(100):
                    if process.poll() is not None:
                        raise AssertionError((work / "runtime.log").read_text())
                    try:
                        api("/version")
                        break
                    except (OSError, urllib.error.URLError):
                        time.sleep(0.02)
                else:
                    raise AssertionError("runtime did not start")
                pid = process.pid
                assert traffic() == "A"
                monitor_thread = threading.Thread(target=monitor, daemon=True)
                monitor_thread.start()
                provider_url = "/providers/proxies/anticheburnet-subscriptions"

                def update(value):
                    write(value)
                    started = time.monotonic()
                    api(provider_url, "PUT")
                    timings.append(round((time.monotonic() - started) * 1000, 3))
                    live = api(provider_url)
                    assert live["revision"] == hashlib.sha256(path.read_bytes()).hexdigest()
                    confirmation = api(provider_url + "?revision=true")
                    assert set(confirmation) == {"name", "revision"}
                    assert confirmation["revision"] == live["revision"]
                    assert process.poll() is None and process.pid == pid
                    return live

                # Same tag and unchanged selector JSON: new credentials must be
                # used by actual traffic, not only appear in the provider API.
                servers[0].password, servers[0].label = "new", "A-new"
                update(payload([node(password="new")]))
                assert traffic() == "A-new"
                pending_stream = []
                stream_thread = threading.Thread(target=lambda: pending_stream.append(traffic("stream")), daemon=True)
                stream_thread.start()
                assert servers[0].stream_started.wait(3)
                update(payload([node(target=1)]))
                servers[0].stream_release.set()
                stream_thread.join(timeout=3)
                assert pending_stream == ["A-new"], "existing connection was interrupted by provider update"
                assert traffic() == "B"
                update(payload([node(target=1), node("node-b", target=0, password="new")]))
                api("/proxies/proxy-main", "PUT", {"name": "node-b"})
                assert traffic() == "A-new"
                update(payload([node(target=1), node("node-b", target=0, password="new"), node("node-c", target=1)]))
                assert api("/proxies/proxy-main")["now"] == "node-b"
                assert traffic() == "A-new"
                update(payload([node(target=1)]))
                proxies = api("/proxies")["proxies"]
                assert "node-b" not in proxies and "node-c" not in proxies
                assert traffic() == "B"
                revision = api(provider_url)["revision"]
                invalid_values = ({"outbounds": []}, payload([node(target=1)], ["missing-node"]), {"outbounds": [node(), node()]}, {"outbounds": [{"type": "unknown", "tag": "bad"}]}, payload([node(target=1), {"type": "selector", "tag": "cycle", "outbounds": ["cycle"]}]), {"outbounds": [node(target=1)]})
                for invalid in invalid_values:
                    write(invalid)
                    try:
                        api(provider_url, "PUT")
                    except urllib.error.HTTPError as error:
                        assert error.code == 503
                    else:
                        raise AssertionError("invalid provider was accepted")
                    assert api(provider_url)["revision"] == revision
                    assert traffic() == "B"
                # Same payload is idempotent and leaves selected outbound alive.
                update(payload([node(target=1)]))
                assert traffic() == "B"
                stop.set()
                monitor_thread.join(timeout=3)
                assert samples and not failures, failures
                result = {"success": True, "pid_before": pid, "pid_after": process.pid, "apply_ms": timings, "availability_samples": len(samples), "availability_failures": failures, "traffic": ["A", "A-new", "B", "A-new", "B"], "existing_connection_preserved": pending_stream == ["A-new"], "rollback_cases": len(invalid_values), "main_config_unchanged": json.loads(config_path.read_text()) == config}
                print(json.dumps(result))
                if args.evidence:
                    Path(args.evidence).write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
            except Exception:
                print((work / "runtime.log").read_text(encoding="utf-8"))
                raise
            finally:
                stop.set()
                for server in servers:
                    server.stream_release.set()
                process.terminate()
                process.wait(timeout=10)
                for server in servers:
                    server.shutdown()


if __name__ == "__main__":
    main()

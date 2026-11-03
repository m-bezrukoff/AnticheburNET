#!/usr/bin/env python3
"""Trace Linux sockets of the packaged core and check default MPTCP policy."""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import time


def free_port(host):
    family = socket.AF_INET6 if ":" in host else socket.AF_INET
    with socket.socket(family) as sock:
        sock.bind((host, 0))
        return sock.getsockname()[1]


def run(args, label, inbounds, api_port=None):
    work = Path(args.work).resolve()
    config = {"inbounds": inbounds, "outbounds": [{"type": "direct"}]}
    if api_port:
        config["experimental"] = {"clash_api": {"external_controller": f"127.0.0.1:{api_port}"}}
    path = work / (label + ".json")
    path.write_text(json.dumps(config), encoding="utf-8")
    trace = work / (label + ".strace")
    command = ["strace", "-f", "-e", "trace=socket", "-o", str(trace)]
    if args.runner:
        command.append(args.runner)
    command += [str(Path(args.binary).resolve()), "run", "-c", str(path)]
    # Check the binary default, not a policy supplied by the test environment.
    env = dict(os.environ)
    env.pop("GODEBUG", None)
    endpoints = [(inbound["listen"], inbound["listen_port"]) for inbound in inbounds]
    if api_port:
        endpoints.append(("127.0.0.1", api_port))
    with (work / (label + ".log")).open("w", encoding="utf-8") as log:
        proc = subprocess.Popen(command, stdout=log, stderr=log, env=env, start_new_session=True)
        try:
            deadline = time.monotonic() + 30
            for endpoint in endpoints:
                while True:
                    if proc.poll() is not None:
                        raise RuntimeError(f"{label}: core exited before listening")
                    try:
                        with socket.create_connection(endpoint, timeout=.5):
                            break
                    except OSError:
                        if time.monotonic() >= deadline:
                            raise RuntimeError(f"{label}: listener {endpoint} did not start")
                        time.sleep(.1)
        finally:
            # Terminate both strace and its tracee, including all emulator threads.
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=5)
    return trace.read_text(encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True)
    parser.add_argument("--runner")
    parser.add_argument("--work", required=True)
    args = parser.parse_args()
    Path(args.work).mkdir(parents=True, exist_ok=True)
    inbounds = []
    for host, tfo in [("127.0.0.1", False), ("127.0.0.1", True), ("::1", False)]:
        inbounds.append({"type": "socks", "listen": host, "listen_port": free_port(host),
                         "tcp_fast_open": tfo})
    trace = run(args, "default", inbounds, free_port("127.0.0.1"))
    mptcp = re.compile(r"socket\([^\n]*,\s*(?:IPPROTO_MPTCP|262)(?=[)\s])")
    if mptcp.search(trace):
        raise AssertionError("Core attempted an MPTCP socket with default inbound/API options")
    # Go uses protocol 0 for ordinary TCP; Linux selects TCP for AF_INET[6]
    # SOCK_STREAM and strace prints that protocol as IPPROTO_IP.
    tcp = re.findall(r"socket\(AF_INET6?,\s*SOCK_STREAM[^\n]*,\s*(?:IPPROTO_IP|IPPROTO_TCP|0|6)(?=[)\s])", trace)
    if len(tcp) < 4:
        raise AssertionError("Trace did not cover IPv4, IPv6, TCP Fast Open and API TCP sockets")
    # Positive control proves the tracer can detect MPTCP even when the Linux
    # kernel refuses it and Go subsequently falls back to TCP.
    explicit = [{"type": "socks", "listen": "127.0.0.1", "listen_port": free_port("127.0.0.1"),
                 "tcp_multi_path": True}]
    if not mptcp.search(run(args, "explicit", explicit)):
        raise AssertionError("Positive control did not expose an explicitly requested MPTCP socket")
    result = {"default_mptcp_attempts": 0, "tcp_sockets": len(tcp),
              "explicit_mptcp_detected": True,
              "checks": ["IPv4", "IPv6", "TCP Fast Open", "Clash API"]}
    (Path(args.work) / "results.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result), flush=True)


if __name__ == "__main__":
    main()

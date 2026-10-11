"""Local HTTP/DNS fixtures: never use a real subscription URL or credentials."""
import base64
import http.server
import ipaddress
import json
import pathlib
import socket
import struct
import sys
import threading

directory = pathlib.Path(sys.argv[1])


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(directory), **kwargs)

    def end_headers(self):
        if self.path.startswith('/subscription') or self.path.startswith('/awg'):
            self.send_header('Routing', (directory / 'routing-header').read_text())
            self.send_header('Routing-Enable', 'true')
        super().end_headers()

    def do_GET(self):
        if self.path == '/source':
            body = self.client_address[0].encode()
            self.send_response(200)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            super().do_GET()


def dns_server():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(('127.0.0.1', 53))
    while True:
        data, peer = sock.recvfrom(65535)
        cursor, labels = 12, []
        while data[cursor]:
            size = data[cursor]
            labels.append(data[cursor + 1:cursor + 1 + size].decode())
            cursor += size + 1
        cursor += 1
        qtype, qclass = struct.unpack('!HH', data[cursor:cursor + 4])
        question = data[12:cursor + 4]
        name = '.'.join(labels)
        address = '192.0.2.1' if name == 'geo.test' else '127.0.0.1'
        # The client DNS response must use the imported DnsHosts mapping.
        if name == 'hosts.test': address = '203.0.113.1'
        answer = b''
        if qtype == 1:
            answer = b'\xc0\x0c' + struct.pack('!HHIH', 1, 1, 60, 4) + ipaddress.ip_address(address).packed
        response = data[:2] + struct.pack('!HHHHH', 0x8180, 1, bool(answer), 0, 0) + question + answer
        sock.sendto(response, peer)


threading.Thread(target=dns_server, daemon=True).start()
http.server.ThreadingHTTPServer(('0.0.0.0', 18081), Handler).serve_forever()

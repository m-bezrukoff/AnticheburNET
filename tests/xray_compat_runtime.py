import argparse
import contextlib
import copy
import datetime
import hashlib
import http.server
import ipaddress
import json
import pathlib
import re
import socket
import ssl
import struct
import subprocess
import threading
import time

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

WORK = None
XRAY = None
SING = None
CAMOUFLAGE = None
RUNNER = []
CASE_FILTER = ''
CREATE_FLAGS = getattr(subprocess, 'CREATE_NO_WINDOW', 0)
UUID = '00000000-0000-4000-8000-000000000001'
BODY = hashlib.sha256(b'AnticheburNET Xray compatibility').digest() * 8192


def port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Length', str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY)

    def log_message(self, *_):
        pass


def recvn(s, n):
    b = b''
    while len(b) < n:
        part = s.recv(n - len(b))
        if not part:
            raise EOFError('SOCKS premature close')
        b += part
    return b


def socks_connect(proxy, dest):
    s = socket.create_connection(('127.0.0.1', proxy), timeout=8)
    s.sendall(b'\x05\x01\x00')
    assert recvn(s, 2) == b'\x05\x00'
    s.sendall(b'\x05\x01\x00\x01\x7f\x00\x00\x01' + struct.pack('!H', dest))
    head = recvn(s, 4)
    assert head[1] == 0, head.hex()
    size = {1: 4, 4: 16}.get(head[3])
    if head[3] == 3:
        size = recvn(s, 1)[0]
    recvn(s, size + 2)
    return s


def udp_fetch(proxy, dest):
    with socket.create_connection(('127.0.0.1', proxy), timeout=8) as control:
        control.sendall(b'\x05\x01\x00')
        assert recvn(control, 2) == b'\x05\x00'
        control.sendall(b'\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00')
        head = recvn(control, 4)
        assert head[1] == 0 and head[3] == 1, head.hex()
        relay = (socket.inet_ntoa(recvn(control, 4)), struct.unpack('!H', recvn(control, 2))[0])
        payload = b'AnticheburNET UDP compatibility'
        packet = b'\x00\x00\x00\x01\x7f\x00\x00\x01' + struct.pack('!H', dest) + payload
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.settimeout(8)
            s.sendto(packet, relay)
            reply, _ = s.recvfrom(4096)
            assert reply.endswith(payload), reply


def fetch(proxy, dest, tls=False):
    try:
        s = socks_connect(proxy, dest)
    except Exception as exc:
        raise RuntimeError(f'SOCKS handshake (innerTLS={tls}): {exc}') from exc
    if tls:
        ctx = ssl.create_default_context(cafile=str(WORK / 'cert.pem'))
        s = ctx.wrap_socket(s, server_hostname='localhost')
    with s:
        s.sendall(b'GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n')
        result = b''
        while True:
            part = s.recv(65536)
            if not part:
                break
            result += part
            if b'\r\n\r\n' in result and len(result.split(b'\r\n\r\n', 1)[1]) >= len(BODY):
                break
    head, body = result.split(b'\r\n\r\n', 1)
    assert b'200 OK' in head and body == BODY, (head, len(body))


@contextlib.contextmanager
def running(exe, config, label):
    path = WORK / (label + '.json')
    path.write_text(json.dumps(config), encoding='utf-8')
    args = [str(exe), 'run', '-config' if exe == XRAY else '-c', str(path)]
    check = args[:2] + (['-test'] if exe == XRAY else []) + args[2:]
    if exe != XRAY:
        check[1] = 'check'
    cp = subprocess.run(RUNNER + check, capture_output=True, timeout=15)
    if cp.returncode:
        raise RuntimeError(cp.stderr.decode(errors='replace'))
    with (WORK / (label + '.log')).open('w', encoding='utf-8') as log:
        proc = subprocess.Popen(RUNNER + args, stdout=log, stderr=log, creationflags=CREATE_FLAGS)
        try:
            time.sleep(.3)
            if proc.poll() is not None:
                raise RuntimeError((WORK / (label + '.log')).read_text())
            yield
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()


def main():
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'localhost')])
    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
            .public_key(key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(now-datetime.timedelta(days=1)).not_valid_after(now+datetime.timedelta(days=2))
            .add_extension(x509.SubjectAlternativeName([x509.DNSName('localhost'), x509.IPAddress(ipaddress.ip_address('127.0.0.1'))]), critical=False)
            # REALITY needs enough target handshake bytes for its ML-DSA proof.
            .add_extension(x509.UnrecognizedExtension(x509.ObjectIdentifier('1.3.6.1.4.1.55555.1'), b'P' * 4096), critical=False)
            .sign(key, hashes.SHA256()))
    (WORK/'cert.pem').write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    (WORK/'key.pem').write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    httpd = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    httpsd = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_3
    ctx.load_cert_chain(str(WORK/'cert.pem'), str(WORK/'key.pem'))
    httpsd.socket = ctx.wrap_socket(httpsd.socket, server_side=True)
    for srv in [httpd, httpsd]:
        threading.Thread(target=srv.serve_forever, daemon=True).start()
    camo_port = port()
    camo_log = (WORK/'camouflage.log').open('w')
    camo = subprocess.Popen([str(CAMOUFLAGE), str(camo_port), str(WORK/'cert.pem'), str(WORK/'key.pem')], stdout=camo_log, stderr=camo_log, creationflags=CREATE_FLAGS)
    import atexit
    atexit.register(camo.terminate)
    time.sleep(.3)
    import urllib.request
    assert urllib.request.urlopen(f'http://127.0.0.1:{httpd.server_port}').read() == BODY
    keypair = subprocess.check_output(RUNNER + [str(XRAY), 'x25519'], text=True)
    private = keypair.split('PrivateKey: ')[1].splitlines()[0]
    public = keypair.split('Password (PublicKey): ')[1].splitlines()[0]
    echo = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    echo.bind(('127.0.0.1', 0))
    def echo_loop():
        while True:
            try:
                b, addr = echo.recvfrom(4096)
                echo.sendto(b, addr)
            except OSError:
                break
    threading.Thread(target=echo_loop, daemon=True).start()
    enc_output = subprocess.check_output(RUNNER + [str(XRAY), 'vlessenc'], text=True)
    enc_values = re.findall(r'"(decryption|encryption)": "([^"]+)"', enc_output)
    encryption_pairs = [(enc_values[i][1], enc_values[i+1][1]) for i in range(0, len(enc_values), 2)]
    mldsa = subprocess.check_output(RUNNER + [str(XRAY), 'mldsa65'], text=True)
    seed = mldsa.split('Seed: ')[1].splitlines()[0]
    verify = mldsa.split('Verify: ')[1].splitlines()[0]
    wrong = subprocess.check_output(RUNNER + [str(XRAY), 'mldsa65'], text=True).split('Verify: ')[1].splitlines()[0]
    cases = [('raw', '', None), ('raw', 'xtls-rprx-vision', None)]
    cases += [('reality', flow, fp) for flow in ['', 'xtls-rprx-vision'] for fp in ['chrome', 'firefox', 'safari']]
    cases += [('xhttp', mode, None) for mode in ['auto', 'packet-up', 'stream-up', 'stream-one']]
    cases += [('encryption', str(i), None) for i in range(len(encryption_pairs))]
    cases += [('xhttp-reality', mode, 'chrome') for mode in ['auto', 'packet-up', 'stream-up', 'stream-one']]
    cases += [('native-socks-bridge', '', None)]
    cases += [('reality-mldsa', variant, 'chrome') for variant in ['valid', 'wrong-key', 'missing-proof']]
    cases += [('xhttp-split', 'packet-up', None)]
    cases += [('grpc', 'tls', None), ('grpc', 'reality', 'chrome')]
    results = []
    for index, (kind, variant, fp) in enumerate(cases):
        label = '-'.join(filter(None, [kind, variant, fp]))
        if CASE_FILTER and not label.startswith(CASE_FILTER):
            continue
        listen, proxy = port(), port()
        user = {'id': UUID}
        out = {'type': 'vless', 'tag': 'proxy', 'server': '127.0.0.1', 'server_port': listen, 'uuid': UUID}
        stream = {'network': 'raw', 'security': 'none'}
        if variant == 'xtls-rprx-vision':
            user['flow'] = variant
            out['flow'] = variant
        if kind == 'raw' and variant:
            # Vision requires outer TLS or REALITY.
            stream['security'] = 'tls'
            stream['tlsSettings'] = {'certificates': [{'certificateFile': str(WORK/'cert.pem'), 'keyFile': str(WORK/'key.pem')}]}
            out['tls'] = {'enabled': True, 'server_name': 'localhost', 'certificate_path': str(WORK/'cert.pem')}
        if kind in ['reality', 'xhttp-reality', 'reality-mldsa'] or (kind == 'grpc' and variant == 'reality'):
            stream.update(security='reality', realitySettings={'dest': f'127.0.0.1:{camo_port}', 'serverNames': ['localhost'], 'privateKey': private, 'shortIds': ['0123456789abcdef']})
            out['tls'] = {'enabled': True, 'server_name': 'localhost', 'utls': {'enabled': True, 'fingerprint': fp}, 'reality': {'enabled': True, 'public_key': public, 'short_id': '0123456789abcdef', 'support_x25519mlkem768': True}}
        if kind in ['xhttp', 'xhttp-split']:
            stream = {'network': 'xhttp', 'security': 'tls', 'xhttpSettings': {'path': '/compat/', 'mode': 'auto'}, 'tlsSettings': {'alpn': ['h2'], 'certificates': [{'certificateFile': str(WORK/'cert.pem'), 'keyFile': str(WORK/'key.pem')}]}}
            out['transport'] = {'type': 'xhttp', 'path': '/compat/', 'mode': variant, 'x_padding_bytes': '100-1000'}
            out['tls'] = {'enabled': True, 'server_name': 'localhost', 'alpn': ['h2'], 'certificate_path': str(WORK/'cert.pem')}
        if kind == 'xhttp-reality':
            stream.update(network='xhttp', xhttpSettings={'path': '/compat/', 'mode': 'auto'})
            out['transport'] = {'type': 'xhttp', 'path': '/compat/', 'mode': variant, 'x_padding_bytes': '100-1000'}
            out['tls']['alpn'] = ['h2']
        if kind == 'grpc':
            stream.update(network='grpc', grpcSettings={'serviceName': 'compat'})
            out['transport'] = {'type': 'grpc', 'service_name': 'compat'}
            if variant == 'tls':
                stream.update(security='tls', tlsSettings={'alpn': ['h2'], 'certificates': [{'certificateFile': str(WORK/'cert.pem'), 'keyFile': str(WORK/'key.pem')}]})
                out['tls'] = {'enabled': True, 'server_name': 'localhost', 'alpn': ['h2'], 'certificate_path': str(WORK/'cert.pem')}
        if kind == 'reality-mldsa':
            if variant != 'missing-proof': stream['realitySettings']['mldsa65Seed'] = seed
            out['tls']['reality']['mldsa65_verify'] = wrong if variant == 'wrong-key' else verify
        if kind == 'xhttp-split':
            out['transport']['download'] = {'server': '127.0.0.1', 'server_port': listen, 'path': '/compat/', 'x_padding_bytes': '100-1000', 'tls': out['tls']}
        decryption = 'none'
        if kind == 'encryption':
            decryption, out['encryption'] = encryption_pairs[int(variant)]
        server = {'log': {'loglevel': 'debug'}, 'inbounds': [{'listen': '127.0.0.1', 'port': listen, 'protocol': 'vless', 'settings': {'clients': [user], 'decryption': 'none'}, 'streamSettings': stream}], 'outbounds': [{'protocol': 'freedom', 'settings': {'finalRules': [{'action': 'allow', 'ip': ['127.0.0.1']} ]}}]}
        server['inbounds'][0]['settings']['decryption'] = decryption
        client = {'log': {'level': 'debug'}, 'inbounds': [{'type': 'socks', 'listen': '127.0.0.1', 'listen_port': proxy}], 'outbounds': [out], 'route': {'final': 'proxy'}}
        if kind == 'native-socks-bridge':
            server['inbounds'] = [{'listen': '127.0.0.1', 'port': listen, 'protocol': 'socks', 'settings': {'auth': 'noauth', 'udp': True}}]
            client['outbounds'] = [{'type': 'socks', 'tag': 'proxy', 'server': '127.0.0.1', 'server_port': listen, 'version': '5'}]
        reject = kind == 'reality-mldsa' and variant != 'valid'
        try:
            with running(XRAY, server, label+'-server'), running(SING, client, label+'-client'):
                fetch(proxy, httpd.server_port)
                fetch(proxy, httpsd.server_port, True)
                udp_fetch(proxy, echo.getsockname()[1])
            if reject: raise AssertionError('invalid ML-DSA authentication was accepted')
            result = {'case': label, 'ok': True, 'checks': ['HTTP 262144 bytes', 'TLS1.3 HTTP 262144 bytes', 'UDP echo']}
        except Exception as exc:
            result = {'case': label, 'ok': bool(reject and not isinstance(exc, AssertionError)), 'error': str(exc), 'expected_rejection': reject}
        results.append(result)
        print(json.dumps(result), flush=True)
    httpd.shutdown()
    httpsd.shutdown()
    camo.terminate()
    camo.wait(timeout=5)
    camo_log.close()
    echo.close()
    (WORK/'results.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    raise SystemExit(0 if all(r['ok'] for r in results) else 1)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--binary', required=True)
    parser.add_argument('--xray', required=True)
    parser.add_argument('--camouflage', required=True)
    parser.add_argument('--work', required=True)
    parser.add_argument('--runner', default='')
    parser.add_argument('--case', default='')
    args = parser.parse_args()
    WORK = pathlib.Path(args.work).resolve(); WORK.mkdir(parents=True, exist_ok=True)
    SING = pathlib.Path(args.binary).resolve(); XRAY = pathlib.Path(args.xray).resolve()
    CAMOUFLAGE = pathlib.Path(args.camouflage).resolve()
    RUNNER = [args.runner] if args.runner else []
    CASE_FILTER = args.case
    main()

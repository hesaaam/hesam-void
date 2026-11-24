"""Test relays in front of a local sshd:
  2080  raw WebSocket relay: answers 101 then pipes raw bytes to sshd
  2082  framed WebSocket relay: answers 101 then (de)frames WebSocket messages
  2081  HTTP CONNECT proxy
  9999  UDP echo
  5353  tiny DNS responder (answers every A query with 10.9.8.7)
  8099  HTTP server
"""
import base64, hashlib, os, socket, struct, threading, http.server, socketserver

SSHD = ("127.0.0.1", 2222)

def pipe(a, b):
    try:
        while True:
            d = a.recv(65536)
            if not d:
                break
            b.sendall(d)
    except OSError:
        pass
    finally:
        for s in (a, b):
            try: s.shutdown(socket.SHUT_RDWR)
            except OSError: pass

def read_headers(c):
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = c.recv(4096)
        if not chunk:
            return None, b""
        data += chunk
    head, rest = data.split(b"\r\n\r\n", 1)
    return head.decode("latin1"), rest

def accept_key(head):
    for line in head.split("\r\n"):
        if line.lower().startswith("sec-websocket-key:"):
            key = line.split(":", 1)[1].strip()
            return base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
    return "x"

def raw_ws(c):
    head, rest = read_headers(c)
    if head is None:
        c.close(); return
    c.sendall(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n" % accept_key(head)).encode())
    s = socket.create_connection(SSHD)
    if rest: s.sendall(rest)
    threading.Thread(target=pipe, args=(c, s), daemon=True).start()
    pipe(s, c)

def frame(data):
    n = len(data)
    if n < 126: h = struct.pack("!BB", 0x82, n)
    elif n < 65536: h = struct.pack("!BBH", 0x82, 126, n)
    else: h = struct.pack("!BBQ", 0x82, 127, n)
    return h + data

def framed_ws(c):
    head, rest = read_headers(c)
    if head is None:
        c.close(); return
    c.sendall(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n" % accept_key(head)).encode())
    s = socket.create_connection(SSHD)
    def up():
        buf = rest
        try:
            while True:
                while True:
                    if len(buf) < 2: break
                    b1 = buf[1]; ln = b1 & 0x7f; pos = 2
                    if ln == 126:
                        if len(buf) < 4: break
                        ln = struct.unpack("!H", buf[2:4])[0]; pos = 4
                    elif ln == 127:
                        if len(buf) < 10: break
                        ln = struct.unpack("!Q", buf[2:10])[0]; pos = 10
                    if len(buf) < pos + 4 + ln: break
                    mask = buf[pos:pos+4]; pos += 4
                    payload = bytes(x ^ mask[i % 4] for i, x in enumerate(buf[pos:pos+ln]))
                    buf = buf[pos+ln:]
                    s.sendall(payload)
                d = c.recv(65536)
                if not d: break
                buf += d
        except OSError:
            pass
        finally:
            try: s.shutdown(socket.SHUT_RDWR)
            except OSError: pass
    threading.Thread(target=up, daemon=True).start()
    try:
        while True:
            d = s.recv(65536)
            if not d: break
            c.sendall(frame(d))
    except OSError:
        pass
    finally:
        try: c.shutdown(socket.SHUT_RDWR)
        except OSError: pass

def connect_proxy(c):
    head, rest = read_headers(c)
    if head is None:
        c.close(); return
    target = head.split(" ")[1]
    host, port = target.rsplit(":", 1)
    s = socket.create_connection((host, int(port)))
    c.sendall(b"HTTP/1.1 200 Connection established\r\n\r\n")
    if rest: s.sendall(rest)
    threading.Thread(target=pipe, args=(c, s), daemon=True).start()
    pipe(s, c)

def serve_tcp(port, handler):
    srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port)); srv.listen(64)
    while True:
        c, _ = srv.accept()
        threading.Thread(target=handler, args=(c,), daemon=True).start()

def udp_echo():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.bind(("127.0.0.1", 9999))
    while True:
        d, a = s.recvfrom(65535); s.sendto(b"echo:" + d, a)

def dns_answer(q):
    tid = q[:2]; qd = q[12:]
    end = qd.index(b"\x00") + 5
    question = qd[:end]
    hdr = tid + b"\x81\x80" + b"\x00\x01\x00\x01\x00\x00\x00\x00"
    ans = b"\xc0\x0c\x00\x01\x00\x01\x00\x00\x00\x3c\x00\x04" + bytes([10, 9, 8, 7])
    return hdr + question + ans

def dns_udp(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.bind(("127.0.0.1", port))
    while True:
        d, a = s.recvfrom(4096)
        try: s.sendto(dns_answer(d), a)
        except Exception: pass

def dns_tcp_handler(c):
    try:
        while True:
            h = c.recv(2)
            if len(h) < 2: break
            n = struct.unpack("!H", h)[0]; q = b""
            while len(q) < n: q += c.recv(n - len(q))
            a = dns_answer(q); c.sendall(struct.pack("!H", len(a)) + a)
    except Exception:
        pass
    c.close()

class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass

def http_server():
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    socketserver.ThreadingTCPServer(("127.0.0.1", 8099), Quiet).serve_forever()

for t in [
    (serve_tcp, (2080, raw_ws)), (serve_tcp, (2082, framed_ws)), (serve_tcp, (2081, connect_proxy)),
    (udp_echo, ()), (dns_udp, (5353,)), (serve_tcp, (5353, dns_tcp_handler)), (http_server, ()),
]:
    threading.Thread(target=t[0], args=t[1], daemon=True).start()
threading.Event().wait()

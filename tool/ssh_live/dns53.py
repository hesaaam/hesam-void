import socket, struct, threading, importlib.util, sys
spec = importlib.util.spec_from_file_location("r", sys.argv[1]); r = importlib.util.module_from_spec(spec)
# reuse dns_answer without starting the relays
src = open(sys.argv[1]).read().split("for t in [")[0]
exec(compile(src, "relays", "exec"), r.__dict__)
def udp():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.bind(("127.0.0.2", 53))
    while True:
        d, a = s.recvfrom(4096); s.sendto(r.dns_answer(d), a)
def tcp():
    srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); srv.bind(("127.0.0.2", 53)); srv.listen(16)
    while True:
        c, _ = srv.accept(); threading.Thread(target=r.dns_tcp_handler, args=(c,), daemon=True).start()
threading.Thread(target=udp, daemon=True).start(); tcp()

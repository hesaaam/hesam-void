#!/usr/bin/env bash
# Starts the servers test/ssh_engine_live_test.dart talks to, on 127.0.0.1.
# Linux, as root. Needs openssh-server, stunnel4, python3, and badvpn-udpgw
# (build it from https://github.com/ambrop72/badvpn with
#  cmake -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 and pass its path).
# Then run:
#   HV_SSH_LIVE=1 HV_SSH_PASSWORD=Test-Pass-123 HV_SSH_KEY=$WORK/client_key \
#     flutter test test/ssh_engine_live_test.dart
# The transparent DNS test points /etc/resolv.conf at 127.0.0.2; the
# original is saved as $WORK/resolv.conf.bak — restore it afterwards.
set -euo pipefail
UDPGW=${1:?usage: start.sh /path/to/badvpn-udpgw}
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-/tmp/hv-ssh-live}
mkdir -p "$WORK" /run/sshd
id hvtest >/dev/null 2>&1 || useradd -m -s /bin/bash hvtest
echo 'hvtest:Test-Pass-123' | chpasswd
[ -f "$WORK/host_ed25519" ] || ssh-keygen -q -t ed25519 -N '' -f "$WORK/host_ed25519"
[ -f "$WORK/client_key" ] || ssh-keygen -q -t ed25519 -N '' -f "$WORK/client_key"
install -d -o hvtest -g hvtest -m 700 /home/hvtest/.ssh
install -o hvtest -g hvtest -m 600 "$WORK/client_key.pub" /home/hvtest/.ssh/authorized_keys
echo "Account expires: 2026-12-31" > "$WORK/banner.txt"
echo "hello-through-ssh" > "$WORK/hello.txt"
cat > "$WORK/sshd_config" <<CONF
Port 2222
ListenAddress 127.0.0.1
HostKey $WORK/host_ed25519
PasswordAuthentication yes
KbdInteractiveAuthentication no
PubkeyAuthentication yes
UsePAM no
PermitRootLogin no
AllowTcpForwarding yes
Banner $WORK/banner.txt
PidFile $WORK/sshd.pid
CONF
/usr/sbin/sshd -f "$WORK/sshd_config"
[ -f "$WORK/tls.crt" ] || openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$WORK/tls.key" -out "$WORK/tls.crt" -days 30 -subj /CN=selfsigned.test 2>/dev/null
cat > "$WORK/stunnel.conf" <<CONF
pid = $WORK/stunnel.pid
[ssh-tls]
accept = 127.0.0.1:2443
connect = 127.0.0.1:2222
cert = $WORK/tls.crt
key = $WORK/tls.key
CONF
stunnel "$WORK/stunnel.conf"
cp "$HERE/relays.py" "$WORK/relays.py"
(cd "$WORK" && nohup python3 -I relays.py >"$WORK/relays.log" 2>&1 &)
nohup python3 -I "$HERE/dns53.py" "$HERE/relays.py" >"$WORK/dns53.log" 2>&1 &
nohup "$UDPGW" --listen-addr 127.0.0.1:7300 --loglevel warning >"$WORK/udpgw.log" 2>&1 &
cp /etc/resolv.conf "$WORK/resolv.conf.bak"
printf 'nameserver 127.0.0.2\n' > /etc/resolv.conf
echo "Servers started; work files in $WORK"

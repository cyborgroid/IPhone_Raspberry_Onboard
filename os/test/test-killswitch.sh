#!/usr/bin/env bash
# Tests the kill-switch against real packets and a real WireGuard tunnel between
# two network namespaces. Runs inside a throwaway container; touches no host
# firewall. Run through: docker run --rm --cap-add NET_ADMIN --cap-add SYS_ADMIN \
#   -v "$PWD/os:/os:ro" ubuntu:26.04 /os/test/test-killswitch.sh
set -uo pipefail

apt-get update -qq >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
  iptables iproute2 wireguard-tools iputils-ping python3 >/dev/null 2>&1 || { echo "apt failed"; exit 2; }

KS=/os/overlay/usr/lib/cyborgroid/wireguard-killswitch.sh
WORK=$(mktemp -d)
export KILLSWITCH_CONF="$WORK/ks.conf"
pass=0; fail=0
check() { # name expected(ok|blocked) command...
  local name=$1 want=$2; shift 2
  local got=blocked
  if "$@" >/dev/null 2>&1; then got=ok; fi
  if [ "$got" = "$want" ]; then echo "  PASS  $name ($got)"; pass=$((pass + 1))
  else echo "  FAIL  $name (want $want, got $got)"; fail=$((fail + 1)); fi
}
dev() { ip netns exec device "$@"; }
ks() { ip netns exec device "$KS" "$@"; }

ip netns add device; ip netns add world
ip link add veth-d netns device type veth peer name veth-w netns world
dev ip link set lo up; dev ip link set veth-d up
ip netns exec world ip link set lo up; ip netns exec world ip link set veth-w up
dev ip addr add 10.99.0.1/24 dev veth-d
dev ip addr add 192.168.77.1/24 dev veth-d
dev ip -6 addr add fd99::1/64 dev veth-d nodad
ip netns exec world ip addr add 10.99.0.2/24 dev veth-w
ip netns exec world ip addr add 192.168.77.2/24 dev veth-w
ip netns exec world ip -6 addr add fd99::2/64 dev veth-w nodad

# UDP echo in the world namespace, to observe what actually gets out.
cat > "$WORK/echo.py" <<'PY'
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("0.0.0.0", int(sys.argv[1])))
while True:
    d, a = s.recvfrom(100); s.sendto(d, a)
PY
cat > "$WORK/probe.py" <<'PY'
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(1)
s.sendto(b"x", (sys.argv[1], int(sys.argv[2])))
s.recvfrom(100)
PY
ip netns exec world python3 "$WORK/echo.py" 53 & E1=$!
ip netns exec world python3 "$WORK/echo.py" 51820 & E2=$!
sleep 0.5
probe() { dev python3 "$WORK/probe.py" "$@"; }
ping4() { dev ping -c1 -W1 "$@"; }
ping6() { dev ping -6 -c1 -W1 "$@"; }

cat > "$WORK/wg-endpoint-only.conf" <<'EOC'
[Peer]
PublicKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
Endpoint = 10.99.0.2:51820
EOC
printf 'WG_CONF=%s\nALLOW_LAN=0\nMARKER=%s\n' "$WORK/wg-endpoint-only.conf" "$WORK/marker" > "$KILLSWITCH_CONF"

echo "== before the kill-switch: everything gets out"
check "IPv4 ping" ok ping4 10.99.0.2
check "IPv6 ping" ok ping6 fd99::2
check "UDP 53" ok probe 10.99.0.2 53

echo "== kill-switch up, default config"
check "script succeeds" ok ks up
check "IPv4 ping leak" blocked ping4 10.99.0.2
check "IPv6 ping leak" blocked ping6 fd99::2
check "plain DNS leak" blocked probe 10.99.0.2 53
check "192.168.0.0/16 hole from the spec" blocked ping4 192.168.77.2
check "UDP to the VPN endpoint itself" ok probe 10.99.0.2 51820
check "UDP 51820 to some other host" blocked probe 192.168.77.2 51820
check "inbound ping from the network" blocked ip netns exec world ping -c1 -W1 10.99.0.1
check "marker written" ok test -e "$WORK/marker"
ks status | grep -q '^active$' && check "status reports active" ok true || check "status reports active" ok false

echo "== ALLOW_LAN=1 opens private ranges only"
printf 'WG_CONF=%s\nALLOW_LAN=1\nMARKER=%s\n' "$WORK/wg-endpoint-only.conf" "$WORK/marker" > "$KILLSWITCH_CONF"
ks up >/dev/null
check "LAN ping allowed" ok ping4 192.168.77.2
check "IPv6 ULA still blocked" blocked ping6 fd99::2
printf 'WG_CONF=%s\nALLOW_LAN=0\nMARKER=%s\n' "$WORK/wg-endpoint-only.conf" "$WORK/marker" > "$KILLSWITCH_CONF"

echo "== fails closed on an unusable config"
printf '[Peer]\nEndpoint = vpn.example.com:51820\n' > "$WORK/wg-host.conf"
printf 'WG_CONF=%s\nMARKER=%s\n' "$WORK/wg-host.conf" "$WORK/marker" > "$KILLSWITCH_CONF"
check "hostname endpoint makes the script fail" blocked ks up
check "and the firewall stays shut" blocked ping4 10.99.0.2
printf 'WG_CONF=%s\nMARKER=%s\n' "$WORK/does-not-exist.conf" "$WORK/marker" > "$KILLSWITCH_CONF"
check "missing config makes the script fail" blocked ks up
check "and the firewall stays shut" blocked ping4 10.99.0.2

echo "== real WireGuard tunnel through the kill-switch"
if ip netns exec world ip link add wgw type wireguard 2>/dev/null; then
  wg genkey > "$WORK/d.key"; wg pubkey < "$WORK/d.key" > "$WORK/d.pub"
  wg genkey > "$WORK/w.key"; wg pubkey < "$WORK/w.key" > "$WORK/w.pub"
  kill "$E2" 2>/dev/null; sleep 0.2
  ip netns exec world wg set wgw listen-port 51820 private-key "$WORK/w.key" \
    peer "$(cat "$WORK/d.pub")" allowed-ips 10.200.0.1/32
  ip netns exec world ip addr add 10.200.0.2/24 dev wgw
  ip netns exec world ip link set wgw up
  printf '[Peer]\nPublicKey = %s\nEndpoint = 10.99.0.2:51820\nAllowedIPs = 10.200.0.0/24\n' "$(cat "$WORK/w.pub")" > "$WORK/wg0.conf"
  printf 'WG_CONF=%s\nMARKER=%s\n' "$WORK/wg0.conf" "$WORK/marker" > "$KILLSWITCH_CONF"
  check "kill-switch up with the tunnel config" ok ks up
  dev ip link add wg0 type wireguard
  dev wg set wg0 private-key "$WORK/d.key" \
    peer "$(cat "$WORK/w.pub")" endpoint 10.99.0.2:51820 allowed-ips 10.200.0.0/24
  dev ip addr add 10.200.0.1/24 dev wg0
  dev ip link set wg0 up
  check "ping through the tunnel" ok ping4 -W3 10.200.0.2
  dev wg show wg0 latest-handshakes | awk '{exit !($2 > 0)}' \
    && check "handshake completed" ok true || check "handshake completed" ok false
  check "direct traffic still blocked" blocked ping4 10.99.0.2
  dev ip link del wg0
  check "tunnel gone: still blocked" blocked ping4 10.99.0.2
  check "tunnel gone: DNS still blocked" blocked probe 10.99.0.2 53
else
  echo "  SKIP  kernel cannot create wireguard interfaces here"
fi

echo "== down restores traffic"
printf 'WG_CONF=%s\nMARKER=%s\n' "$WORK/wg-endpoint-only.conf" "$WORK/marker" > "$KILLSWITCH_CONF"
check "script succeeds" ok ks down
check "IPv4 ping back" ok ping4 10.99.0.2
check "IPv6 ping back" ok ping6 fd99::2
check "marker removed" blocked test -e "$WORK/marker"

kill "$E1" "$E2" 2>/dev/null
echo; echo "passed=$pass failed=$fail"
[ "$fail" = 0 ]

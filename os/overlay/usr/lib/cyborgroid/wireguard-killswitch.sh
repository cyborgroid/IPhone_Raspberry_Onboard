#!/usr/bin/env bash
# WireGuard kill-switch: anything not going through the tunnel is dropped, for
# IPv4 and IPv6. It fails closed: an unusable config leaves the firewall shut.
#
#   wireguard-killswitch.sh up|down|status
#
# Settings come from /etc/cyborgroid/killswitch.conf (see that file).

set -uo pipefail

CONF_FILE="${KILLSWITCH_CONF:-/etc/cyborgroid/killswitch.conf}"
WG_IF="wg0"
WG_CONF="/etc/wireguard/wg0.conf"
ALLOW_LAN=0
MARKER="/run/cyborgroid-net/killswitch.active"
# shellcheck source=/dev/null
[ -r "$CONF_FILE" ] && . "$CONF_FILE"

if [ "$EUID" -ne 0 ]; then
  echo "[!] root 권한으로 실행해야 합니다 (sudo)" >&2
  exit 1
fi

# Policies go to DROP before the flush, so no packet can pass between the two.
close_all() {
  local ipt
  for ipt in iptables ip6tables; do
    "$ipt" -P INPUT DROP
    "$ipt" -P FORWARD DROP
    "$ipt" -P OUTPUT DROP
    "$ipt" -F
    "$ipt" -X
    "$ipt" -A INPUT -i lo -j ACCEPT
    "$ipt" -A OUTPUT -o lo -j ACCEPT
    "$ipt" -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    "$ipt" -A OUTPUT -o "$WG_IF" -j ACCEPT
    "$ipt" -A INPUT -i "$WG_IF" -j ACCEPT
  done

  # DHCP, or the uplink never gets an address on a non-192.168 network.
  iptables -A OUTPUT -p udp --sport 68 --dport 67 -j ACCEPT
  iptables -A INPUT -p udp --sport 67 --dport 68 -j ACCEPT
  # Neighbour discovery: the IPv6 equivalent of ARP, which iptables never sees.
  local type
  for type in 133 134 135 136; do
    ip6tables -A OUTPUT -p ipv6-icmp --icmpv6-type "$type" -m hl --hl-eq 255 -j ACCEPT
    ip6tables -A INPUT -p ipv6-icmp --icmpv6-type "$type" -m hl --hl-eq 255 -j ACCEPT
  done

  if [ "$ALLOW_LAN" = "1" ]; then
    local net
    for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
      iptables -A OUTPUT -d "$net" -j ACCEPT
      iptables -A INPUT -s "$net" -j ACCEPT
    done
    ip6tables -A OUTPUT -d fe80::/10 -j ACCEPT
    ip6tables -A INPUT -s fe80::/10 -j ACCEPT
  fi
}

# Opens exactly host:port for each peer. A hostname cannot be used, because DNS
# is blocked until the tunnel it would be needed for is up.
allow_endpoints() {
  local status=0 found=0 endpoint host port ipt
  [ -r "$WG_CONF" ] || { echo "[!] $WG_CONF 를 읽을 수 없어 차단 상태로 둡니다" >&2; return 1; }
  while read -r endpoint; do
    found=1
    port="${endpoint##*:}"
    host="${endpoint%:*}"
    case "$host" in
      \[*\]) host="${host#[}"; host="${host%]}"; ipt=ip6tables ;;
      *[!0-9.]*) echo "[!] Endpoint '$endpoint' 는 IP 주소가 아닙니다. IP로 지정해야 합니다" >&2; status=1; continue ;;
      *) ipt=iptables ;;
    esac
    "$ipt" -A OUTPUT -d "$host" -p udp --dport "$port" -j ACCEPT || status=1
  done < <(sed -nE 's/^[[:space:]]*Endpoint[[:space:]]*=[[:space:]]*([^[:space:]#]+).*/\1/p' "$WG_CONF")
  [ "$found" = 1 ] || { echo "[!] $WG_CONF 에 Endpoint 가 없습니다" >&2; status=1; }
  return "$status"
}

case "${1:-up}" in
  up)
    close_all || exit 1
    mkdir -p "$(dirname "$MARKER")"
    touch "$MARKER"
    if ! allow_endpoints; then
      echo "[!] 킬스위치는 켜졌지만 VPN 서버로 나가는 경로가 없습니다. 외부 통신이 끊긴 상태입니다." >&2
      exit 1
    fi
    echo "[+] WireGuard 킬스위치가 활성화되었습니다."
    ;;
  down)
    for ipt in iptables ip6tables; do
      "$ipt" -F
      "$ipt" -X
      "$ipt" -P INPUT ACCEPT
      "$ipt" -P FORWARD ACCEPT
      "$ipt" -P OUTPUT ACCEPT
    done
    rm -f "$MARKER"
    echo "[-] 킬스위치를 해제했습니다. 트래픽이 VPN 없이 나갈 수 있습니다."
    ;;
  status)
    if [ -e "$MARKER" ]; then echo "active"; else echo "inactive"; fi
    ;;
  *)
    echo "usage: $0 up|down|status" >&2
    exit 2
    ;;
esac

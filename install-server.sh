#!/bin/bash
# AmneziaWG one-command server installer (Ubuntu/Debian)
# https://github.com/sotnick1-glitch/amneziawg-server-installer
#
# What this does:
#   - Installs the AmneziaWG kernel module + tools on your own VPS
#   - Sets up a server interface with random obfuscation parameters
#   - Generates a client, and prints/saves a ready-to-use client .conf
#     (feed that .conf into https://github.com/sotnick1-glitch/amneziawg-openwrt-installer
#      or any AmneziaWG-compatible app: AmneziaWG, AmneziaVPN, DefaultVPN, WG Tunnel...)
#
# This script is generic: it does not contain any pre-set server, keys,
# or accounts. Everything is generated fresh, on YOUR OWN machine, when
# you run it.
#
# Usage (as root):
#   curl -fsSL https://raw.githubusercontent.com/sotnick1-glitch/amneziawg-server-installer/main/install-server.sh | bash

set -e

CONF_DIR="/etc/amnezia/amneziawg"
IFACE="awg0"
PORT="${AWG_PORT:-51820}"
SUBNET="10.29.29"

if [ "$(id -u)" -ne 0 ]; then
	echo "Run this as root (sudo -i, then re-run)." >&2
	exit 1
fi

# --- 1. Detect public IP / endpoint -----------------------------------------
PUB_IP=$(curl -fsSL -4 https://ifconfig.me 2>/dev/null || curl -fsSL -4 https://api.ipify.org 2>/dev/null || true)
read -rp "Endpoint (public IP or domain of this server) [$PUB_IP]: " ENDPOINT_HOST
ENDPOINT_HOST="${ENDPOINT_HOST:-$PUB_IP}"
if [ -z "$ENDPOINT_HOST" ]; then
	echo "Could not detect a public IP automatically — enter it manually next time." >&2
	exit 1
fi

# --- 2. Install packages -----------------------------------------------------
if ! command -v awg >/dev/null 2>&1; then
	echo "--> Installing AmneziaWG..."
	. /etc/os-release
	apt-get update -qq
	apt-get install -y -qq software-properties-common gnupg2 "linux-headers-$(uname -r)" >/dev/null
	if [ "$ID" = "ubuntu" ]; then
		add-apt-repository -y ppa:amnezia/ppa >/dev/null
	else
		echo "deb https://ppa.launchpadcontent.net/amnezia/ppa/ubuntu noble main" > /etc/apt/sources.list.d/amnezia.list
		apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 57290828 >/dev/null 2>&1 || true
	fi
	apt-get update -qq
	apt-get install -y amneziawg
else
	echo "--> AmneziaWG already installed, skipping."
fi

modprobe amneziawg 2>/dev/null || true

# --- 3. Detect the outbound network interface -------------------------------
NIC=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}')
if [ -z "$NIC" ]; then
	read -rp "Could not auto-detect your network interface, enter it (e.g. eth0): " NIC
fi

# --- 4. Generate server keys + obfuscation params, if not already set -------
mkdir -p "$CONF_DIR"
umask 077

if [ ! -f "$CONF_DIR/awg0.conf" ]; then
	echo "--> First-time setup: generating server keys and obfuscation parameters..."
	awg genkey | tee "$CONF_DIR/server_private.key" | awg pubkey > "$CONF_DIR/server_public.key"

	JC=$(( (RANDOM % 7) + 3 ))          # 3-9
	JMIN=$(( (RANDOM % 30) + 30 ))      # 30-59
	JMAX=$(( JMIN + (RANDOM % 60) + 40 ))
	S1=$(( (RANDOM % 100) + 15 ))
	S2=$(( S1 + 56 + (RANDOM % 40) + 1 ))  # keep S1+56 != S2
	H1=$(( (RANDOM * RANDOM) % 4000000000 + 5 ))
	H2=$(( (RANDOM * RANDOM) % 4000000000 + 5 ))
	H3=$(( (RANDOM * RANDOM) % 4000000000 + 5 ))
	H4=$(( (RANDOM * RANDOM) % 4000000000 + 5 ))

	cat > "$CONF_DIR/obfs_params.env" << EOF
JC=$JC
JMIN=$JMIN
JMAX=$JMAX
S1=$S1
S2=$S2
H1=$H1
H2=$H2
H3=$H3
H4=$H4
EOF

	SERVER_PRIV=$(cat "$CONF_DIR/server_private.key")

	cat > "$CONF_DIR/$IFACE.conf" << EOF
[Interface]
PrivateKey = $SERVER_PRIV
Address = $SUBNET.1/24
ListenPort = $PORT
Jc = $JC
Jmin = $JMIN
Jmax = $JMAX
S1 = $S1
S2 = $S2
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4
PostUp = iptables -t nat -A POSTROUTING -s $SUBNET.0/24 -o $NIC -j MASQUERADE; iptables -A FORWARD -i $IFACE -j ACCEPT; iptables -A FORWARD -o $IFACE -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s $SUBNET.0/24 -o $NIC -j MASQUERADE; iptables -D FORWARD -i $IFACE -j ACCEPT; iptables -D FORWARD -o $IFACE -j ACCEPT
EOF
	chmod 600 "$CONF_DIR/$IFACE.conf"

	echo 1 > /proc/sys/net/ipv4/ip_forward
	if ! grep -q '^net.ipv4.ip_forward' /etc/sysctl.conf 2>/dev/null; then
		echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
	fi

	awg-quick up "$IFACE"
	systemctl enable "awg-quick@$IFACE" >/dev/null 2>&1

	echo "--> Server is up and listening on UDP $PORT."
else
	echo "--> Server already configured, adding a new client to it."
fi

# shellcheck disable=SC1091
source "$CONF_DIR/obfs_params.env"
SERVER_PUB=$(cat "$CONF_DIR/server_public.key")

# --- 5. Add a client ----------------------------------------------------------
read -rp "Name for this client (e.g. phone, laptop, router): " CNAME
CNAME="${CNAME:-client}"
NEXT_IP=$(( $(grep -oE "$SUBNET\.[0-9]+/32" "$CONF_DIR/$IFACE.conf" | cut -d. -f4 | cut -d/ -f1 | sort -n | tail -1) + 1 ))
[ -z "$NEXT_IP" ] || [ "$NEXT_IP" -le 1 ] && NEXT_IP=2

awg genkey | tee "$CONF_DIR/client_${CNAME}_private.key" | awg pubkey > "$CONF_DIR/client_${CNAME}_public.key"
awg genpsk > "$CONF_DIR/client_${CNAME}_psk.key"

CLIENT_PRIV=$(cat "$CONF_DIR/client_${CNAME}_private.key")
CLIENT_PUB=$(cat "$CONF_DIR/client_${CNAME}_public.key")
CLIENT_PSK=$(cat "$CONF_DIR/client_${CNAME}_psk.key")

awg set "$IFACE" peer "$CLIENT_PUB" preshared-key <(echo "$CLIENT_PSK") allowed-ips "$SUBNET.$NEXT_IP/32"

cat >> "$CONF_DIR/$IFACE.conf" << EOF

[Peer]
PublicKey = $CLIENT_PUB
PresharedKey = $CLIENT_PSK
AllowedIPs = $SUBNET.$NEXT_IP/32
EOF

OUT="$CONF_DIR/client_${CNAME}.conf"
cat > "$OUT" << EOF
[Interface]
PrivateKey = $CLIENT_PRIV
Address = $SUBNET.$NEXT_IP/32
DNS = 1.1.1.1, 1.0.0.1
Jc = $JC
Jmin = $JMIN
Jmax = $JMAX
S1 = $S1
S2 = $S2
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4

[Peer]
PublicKey = $SERVER_PUB
PresharedKey = $CLIENT_PSK
Endpoint = $ENDPOINT_HOST:$PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
chmod 600 "$OUT"

echo ""
echo "=== Done ==="
echo "Client config saved to: $OUT"
echo ""
echo "--- copy everything between the lines below into the app or the OpenWrt installer ---"
echo "-----------------------------------------------------------------------------------"
cat "$OUT"
echo "-----------------------------------------------------------------------------------"
echo ""
echo "Import it into the AmneziaWG / AmneziaVPN app, or paste it into the"
echo "amneziawg-openwrt-installer script on your router."

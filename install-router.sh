#!/bin/sh
# AmneziaWG one-command installer for OpenWrt
# https://github.com/sotnick1-glitch/amneziawg-openwrt-installer
#
# What this does:
#   - Installs AmneziaWG kernel module + tools (if not already present)
#   - Creates a network interface 'awg0' from a client config YOU provide
#   - Adds NAT/firewall so devices on your LAN can use the tunnel
#   - Installs a one-button toggle page inside LuCI (Services -> AmneziaWG)
#
# What this does NOT do:
#   - It does not contain, generate, or phone home any keys/servers.
#   - You must already have a client .conf from YOUR OWN AmneziaWG server
#     (e.g. exported from the Amnezia app, or given to you by your provider).
#   - Nothing here is tied to any specific VPN service.
#
# Usage:
#   ssh root@<your-router-ip>
#   wget -O- https://raw.githubusercontent.com/<user>/<repo>/main/install-amneziawg-openwrt.sh | sh

set -e

IFACE="awg0"
CGI_PATH="/www/cgi-bin/amnezia"
VIEW_PATH="/www/luci-static/resources/view/amnezia.js"
MENU_PATH="/usr/share/luci/menu.d/luci-app-amnezia.json"

echo "=== AmneziaWG installer for OpenWrt ==="

# --- 1. Install packages ---------------------------------------------------
if ! command -v awg >/dev/null 2>&1; then
	echo "--> Installing amneziawg packages..."
	opkg update >/dev/null 2>&1 || true
	if ! opkg install amneziawg-tools kmod-amneziawg luci-proto-amneziawg 2>/dev/null; then
		echo "!!! Packages not found in your feeds."
		echo "    Your OpenWrt build/target may not carry AmneziaWG packages yet."
		echo "    See: https://github.com/amnezia-vpn/amneziawg-openwrt"
		exit 1
	fi
else
	echo "--> AmneziaWG tools already installed, skipping."
fi

modprobe amneziawg 2>/dev/null || true

# --- 2. Get the client config -----------------------------------------------
echo ""
echo "Paste your AmneziaWG client .conf below (the one from YOUR OWN server),"
echo "then press Enter and Ctrl-D on an empty line to finish:"
echo ""
CONF=$(cat)

get_val() {
	echo "$CONF" | grep -i "^$1" | head -1 | cut -d'=' -f2- | tr -d ' \r'
}

PRIVATE_KEY=$(get_val "PrivateKey")
ADDRESS=$(get_val "Address")
DNS=$(get_val "DNS")
JC=$(get_val "Jc")
JMIN=$(get_val "Jmin")
JMAX=$(get_val "Jmax")
S1=$(get_val "S1")
S2=$(get_val "S2")
H1=$(get_val "H1")
H2=$(get_val "H2")
H3=$(get_val "H3")
H4=$(get_val "H4")
PEER_PUBKEY=$(get_val "PublicKey")
PEER_PSK=$(get_val "PresharedKey")
ENDPOINT=$(get_val "Endpoint")
ENDPOINT_HOST=$(echo "$ENDPOINT" | cut -d':' -f1)
ENDPOINT_PORT=$(echo "$ENDPOINT" | cut -d':' -f2)
KEEPALIVE=$(get_val "PersistentKeepalive")
[ -z "$KEEPALIVE" ] && KEEPALIVE=25

if [ -z "$PRIVATE_KEY" ] || [ -z "$PEER_PUBKEY" ] || [ -z "$ENDPOINT_HOST" ]; then
	echo "!!! Could not parse the config. Make sure you pasted a full .conf file."
	exit 1
fi

# --- 3. Write network config -------------------------------------------------
echo "--> Configuring interface $IFACE..."
uci -q delete network.$IFACE
uci set network.$IFACE='interface'
uci set network.$IFACE.proto='amneziawg'
uci set network.$IFACE.private_key="$PRIVATE_KEY"
uci -q delete network.$IFACE.addresses
uci add_list network.$IFACE.addresses="$ADDRESS"
[ -n "$JC" ] && uci set network.$IFACE.awg_jc="$JC"
[ -n "$JMIN" ] && uci set network.$IFACE.awg_jmin="$JMIN"
[ -n "$JMAX" ] && uci set network.$IFACE.awg_jmax="$JMAX"
[ -n "$S1" ] && uci set network.$IFACE.awg_s1="$S1"
[ -n "$S2" ] && uci set network.$IFACE.awg_s2="$S2"
[ -n "$H1" ] && uci set network.$IFACE.awg_h1="$H1"
[ -n "$H2" ] && uci set network.$IFACE.awg_h2="$H2"
[ -n "$H3" ] && uci set network.$IFACE.awg_h3="$H3"
[ -n "$H4" ] && uci set network.$IFACE.awg_h4="$H4"
if [ -n "$DNS" ]; then
	uci -q delete network.$IFACE.dns
	echo "$DNS" | tr ',' '\n' | while read -r d; do
		d=$(echo "$d" | tr -d ' ')
		[ -n "$d" ] && uci add_list network.$IFACE.dns="$d"
	done
fi

uci -q delete network.${IFACE}_peer
uci set network.${IFACE}_peer="amneziawg_${IFACE}"
uci set network.${IFACE}_peer.public_key="$PEER_PUBKEY"
[ -n "$PEER_PSK" ] && uci set network.${IFACE}_peer.preshared_key="$PEER_PSK"
uci -q delete network.${IFACE}_peer.allowed_ips
uci add_list network.${IFACE}_peer.allowed_ips='0.0.0.0/0'
uci set network.${IFACE}_peer.route_allowed_ips='0'
uci set network.${IFACE}_peer.endpoint_host="$ENDPOINT_HOST"
uci set network.${IFACE}_peer.endpoint_port="$ENDPOINT_PORT"
uci set network.${IFACE}_peer.persistent_keepalive="$KEEPALIVE"
uci commit network

# --- 4. Firewall: add interface to an existing masquerading zone ------------
echo "--> Configuring firewall (NAT)..."
WANZONE=$(uci show firewall | grep "\.masq='1'" | head -1 | cut -d'.' -f1-2)
if [ -n "$WANZONE" ]; then
	uci add_list "${WANZONE}.network=$IFACE" 2>/dev/null || true
	uci commit firewall
	/etc/init.d/firewall reload >/dev/null 2>&1 || true
else
	echo "    Warning: no zone with masquerading found. You'll need to add"
	echo "    '$IFACE' to your WAN firewall zone manually."
fi

# --- 5. Bring the interface up (off by default, safe) -----------------------
ifup "$IFACE" >/dev/null 2>&1 || true

# --- 6. Install the toggle page ---------------------------------------------
echo "--> Installing on/off toggle page..."
cat > "$CGI_PATH" << CGISCRIPT
#!/bin/sh
echo 'Content-Type: text/html; charset=utf-8'
echo ''
IFACE='$IFACE'

if [ "\$REQUEST_METHOD" = 'POST' ]; then
	read -r POSTDATA
	case "\$POSTDATA" in
		*action=on*)
			uci set network.\${IFACE}_peer.route_allowed_ips='1'
			uci commit network
			ifdown "\$IFACE" >/dev/null 2>&1
			ifup "\$IFACE" >/dev/null 2>&1
			;;
		*action=off*)
			uci set network.\${IFACE}_peer.route_allowed_ips='0'
			uci commit network
			ifdown "\$IFACE" >/dev/null 2>&1
			ifup "\$IFACE" >/dev/null 2>&1
			for wanif in \$(uci -q get network.wan.device 2>/dev/null); do :; done
			ifup wan >/dev/null 2>&1 || true
			sleep 3
			if [ -z "\$(ip route show default)" ]; then
				GW=\$(ip route show dev pppoe-wan 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
				[ -n "\$GW" ] && ip route add default via "\$GW" dev pppoe-wan 2>/dev/null
			fi
			;;
	esac
	sleep 2
fi

DEFROUTE=\$(ip route show default | grep -c "\$IFACE")
NODEFROUTE=\$(ip route show default | wc -l)
HANDSHAKE=\$(awg show "\$IFACE" latest-handshakes 2>/dev/null | awk '{print \$2}')
NOW=\$(date +%s)

if [ "\$DEFROUTE" -gt 0 ] 2>/dev/null; then
	STATUS='<span style="color:#2ecc71">ON — all traffic via AmneziaWG</span>'
	BTN='<button name="action" value="off" style="background:#e74c3c">Turn off</button>'
else
	STATUS='<span style="color:#888">OFF — normal routing</span>'
	BTN='<button name="action" value="on" style="background:#2ecc71">Turn on</button>'
fi

if [ "\$NODEFROUTE" -eq 0 ] 2>/dev/null; then
	NETWARN='<p style="color:#e74c3c">WARNING: no default route at all. Reload this page.</p>'
else
	NETWARN=''
fi

if [ -n "\$HANDSHAKE" ] && [ "\$HANDSHAKE" != '0' ]; then
	HS_INFO="Last handshake: \$((NOW - HANDSHAKE))s ago"
else
	HS_INFO='No handshake yet'
fi

cat << HTML
<!DOCTYPE html><html><head><meta charset='utf-8'><title>AmneziaWG</title>
<style>
body{font-family:sans-serif;background:#1a1a1a;color:#eee;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}
.card{background:#262626;padding:40px;border-radius:12px;text-align:center;min-width:320px}
button{font-size:16px;padding:12px 24px;border:none;border-radius:6px;color:white;cursor:pointer;margin-top:20px}
.small{color:#888;font-size:13px;margin-top:10px}
</style></head><body><div class='card'>
<h2>AmneziaWG</h2><p>\$STATUS</p><p class='small'>\$HS_INFO</p>\$NETWARN
<form method='post'>\$BTN</form>
<p class='small'><a href='/cgi-bin/amnezia' style='color:#666'>Refresh</a></p>
</div></body></html>
HTML
CGISCRIPT
chmod +x "$CGI_PATH"

mkdir -p "$(dirname "$VIEW_PATH")"
cat > "$VIEW_PATH" << 'JSVIEW'
'use strict';
'require view';
return view.extend({
	render: function() {
		return E('iframe', {
			src: '/cgi-bin/amnezia',
			style: 'width: 100%; min-height: 600px; border: none;'
		});
	},
	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
JSVIEW

cat > "$MENU_PATH" << 'MENUJSON'
{
	"admin/services/amnezia": {
		"title": "AmneziaWG",
		"order": 43,
		"action": { "type": "view", "path": "amnezia" }
	}
}
MENUJSON

rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache* 2>/dev/null
/etc/init.d/rpcd restart >/dev/null 2>&1 || true

echo ""
echo "=== Done ==="
echo "Open your router's admin page -> Services -> AmneziaWG to turn it on/off."
echo "Or directly: http://<router-ip>/cgi-bin/amnezia"
echo "It is OFF by default — nothing changes until you press the button."

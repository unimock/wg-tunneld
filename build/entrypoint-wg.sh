#!/bin/bash
#
# entrypoint-wg.sh - brings up the WireGuard tunnels in the host namespace and
# keeps the wg-reresolve watchdog (cron) running. NO sshd - only the WireGuard runtime.
#
# The WG tunnels are derived directly from flat config files in the mounted
# WG_CONF_DIR: each <wg-name>.conf yields an interface <wg-name>. If the file is
# there, the tunnel is built - no node.yml/state filter.
#
# Because of network_mode: host the wg-* interfaces are created directly in the
# host namespace and are thus usable both on the host and from other (also
# host-networked) containers.
#
set -u

WG_CONF_DIR="${WG_CONF_DIR:-/etc/wireguard}"

log() { echo "[wg] $*"; }

# --- 1. Network sysctls ----------------------------------------------------
# Because of network_mode: host these CANNOT be set via the compose `sysctls:`
# block (runc forbids namespaced net.* sysctls in the host namespace). We set
# them directly on the host:
#   - src_valid_mark=1: otherwise the kernel drops packets with an fwmark set in
#     strict rp_filter mode, which wg-quick uses for its policy routing.
#   - ip_forward=1: routing/forwarding over the wg-* interfaces (needed as soon
#     as other containers route over these tunnels via a bridge).
# Tolerate errors (e.g. read-only /proc/sys) so the container still starts.
set_sysctl() {
    local path="/proc/sys/$1" val="$2"
    echo "$val" > "$path" 2>/dev/null \
        || log "WARN: could not set $1 to $val ($path)."
}
set_sysctl net/ipv4/conf/all/src_valid_mark 1
set_sysctl net/ipv4/ip_forward 1

# --- 2. WG tunnels directly from the flat .conf files ----------------------
# Each <wg-name>.conf in WG_CONF_DIR yields an interface <wg-name>. Since the
# files already live in the WG standard path, wg-quick reads them directly from
# the (read-only) mount - no copy step needed.
if [[ -d "$WG_CONF_DIR" ]]; then
    shopt -s nullglob
    confs=("$WG_CONF_DIR"/*.conf)
    (( ${#confs[@]} == 0 )) && log "No *.conf in $WG_CONF_DIR - no tunnels."

    for conf in "${confs[@]}"; do
        iface="$(basename "$conf" .conf)"

        # Interface name = file name; skip when > 15 characters (IFNAMSIZ) -
        # without a copy step (mount ro) no shortening/renaming is possible.
        if (( ${#iface} > 15 )); then
            log "WARN: interface '$iface' > 15 characters (IFNAMSIZ) - skipped."
            continue
        fi

        # Idempotency: tear down an interface possibly left over in the host
        # namespace from a previous run before rebuilding it.
        if ip link show "$iface" >/dev/null 2>&1; then
            wg-quick down "$iface" 2>/dev/null || ip link del "$iface" 2>/dev/null || true
        fi

        if wg-quick up "$conf"; then
            log "Tunnel '$iface' active."
        else
            log "WARN: 'wg-quick up $conf' failed."
        fi
    done
else
    log "WARN: $WG_CONF_DIR does not exist - no WireGuard tunnels built."
fi

# --- 3. Watchdog (cron) in the foreground as PID-1 holder ------------------
# Only the wg-reresolve job from /etc/cron.d/wg-reresolve (baked into the image).
log "Starting cron (wg-reresolve watchdog) in the foreground."
exec cron -f

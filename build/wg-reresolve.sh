#!/bin/bash
#
# wg-reresolve.sh - WireGuard watchdog
#
# Re-resolves the endpoint hostnames of each peer and sets them again via
# `wg set ... endpoint ...` IF the last handshake is stale. This catches DynDNS
# IP changes after a node/server reboot: `wg-quick` resolves the endpoint only
# once at startup, after which the tunnel would stay dead if the server IP changed.
#
# Usage:
#   wg-reresolve.sh                 -> all active wg-* interfaces
#   wg-reresolve.sh <iface>         -> only this interface
#   wg-reresolve.sh /path/x.conf    -> derive interface from config file
#
# Modeled after the official wireguard-tools reresolve-dns.sh.

set -u
shopt -s nocasematch
export LC_ALL=C

# A peer counts as "stale" if more than this many seconds have passed since its
# last handshake (WireGuard handshake rekey is around ~120s).
STALE_AFTER=135

log() { echo "wg-reresolve: $*"; }

# Re-resolves the endpoints of a single interface.
reresolve_interface() {
    local iface="$1"
    local conf="/etc/wireguard/${iface}.conf"

    if [[ ! -r "$conf" ]]; then
        log "WARN: config $conf not readable, skipping $iface"
        return 0
    fi

    local now handshakes
    now="$(date +%s)"
    # Map: PublicKey -> last handshake (Unix seconds, 0 = never)
    handshakes="$(wg show "$iface" latest-handshakes 2>/dev/null)"

    local in_peer=0 pubkey="" endpoint=""

    _maybe_reresolve() {
        # Only act when the peer section is complete.
        [[ $in_peer -eq 1 && -n "$pubkey" && -n "$endpoint" ]] || return 0

        local last
        last="$(awk -v k="$pubkey" '$1==k {print $2}' <<<"$handshakes")"
        [[ -z "$last" ]] && last=0

        if (( last > now - STALE_AFTER )); then
            return 0   # handshake fresh -> nothing to do
        fi

        if wg set "$iface" peer "$pubkey" endpoint "$endpoint" 2>/dev/null; then
            log "$iface: endpoint re-resolved -> $endpoint (peer ${pubkey:0:8}…, handshake stale)"
        else
            log "WARN: $iface: 'wg set endpoint $endpoint' failed (DNS?)"
        fi
    }

    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Trim comments/whitespace
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue

        if [[ "$line" == "["* ]]; then
            # Section change -> process the previous peer section
            _maybe_reresolve
            pubkey=""; endpoint=""
            [[ "$line" == "[Peer]"* ]] && in_peer=1 || in_peer=0
            continue
        fi

        key="${line%%=*}"
        value="${line#*=}"
        key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"

        case "$key" in
            PublicKey) pubkey="$value" ;;
            Endpoint)  endpoint="$value" ;;
        esac
    done <"$conf"

    _maybe_reresolve   # last peer section
    unset -f _maybe_reresolve
}

main() {
    local targets=()

    if [[ $# -ge 1 ]]; then
        local arg="$1"
        if [[ "$arg" == *.conf ]]; then
            arg="$(basename "$arg" .conf)"
        fi
        targets=("$arg")
    else
        # All active WireGuard interfaces
        local ifaces
        ifaces="$(wg show interfaces 2>/dev/null)"
        for i in $ifaces; do
            targets+=("$i")
        done
    fi

    for t in "${targets[@]}"; do
        reresolve_interface "$t"
    done
}

main "$@"

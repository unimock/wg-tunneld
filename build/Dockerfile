FROM debian:bookworm-slim

# Only the WireGuard runtime: tunnel setup (wg-quick), endpoint reresolve, cron.
#   - openresolv: needed by wg-quick for `DNS =` in the wg.conf (keep internal
#     names resolvable over the tunnels).
#   - procps: provides the `sysctl` binary that wg-quick calls itself in the
#     full-tunnel path (src_valid_mark).
# No python/yaml needed: the WG tunnels are derived via shell directly from the
# flat <wg-name>.conf files in the mounted WG_CONF_DIR.
# NO openssh/sshfs/rsync - only the WireGuard runtime.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        wireguard-tools \
        iproute2 \
        iptables \
        procps \
        openresolv \
        cron \
        tini \
    && rm -rf /var/lib/apt/lists/*

# Install scripts (build context is ./build).
COPY entrypoint-wg.sh /usr/local/bin/entrypoint-wg.sh
COPY wg-reresolve.sh  /usr/local/bin/wg-reresolve.sh
RUN chmod +x /usr/local/bin/entrypoint-wg.sh /usr/local/bin/wg-reresolve.sh

# WireGuard watchdog: re-resolves DynDNS endpoints after a node/server reboot.
RUN printf '* * * * * root /usr/local/bin/wg-reresolve.sh >/dev/null 2>&1\n' \
        > /etc/cron.d/wg-reresolve \
    && chmod 644 /etc/cron.d/wg-reresolve

# tini as PID 1 for clean signal/zombie handling.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint-wg.sh"]

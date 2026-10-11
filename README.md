# wg-tunneld

Lean Debian container that brings up the **WireGuard tunnels**. Tunnels are derived
directly from flat config files in the mounted `/etc/wireguard`: each `<wg-name>.conf`
yields an interface `<wg-name>` (no `nodes/` directory, no `node.yml` state filter — if
the file is there, the tunnel is built). Thanks to `network_mode: host` the tunnels live
**on the host too** and are usable from other host-networked containers. Also keeps the
`wg-reresolve` watchdog running.

The image contains only the WireGuard runtime — no sshd/sshfs/python.

Each tunnel corresponds to a file `/etc/wireguard/<name>.conf`.

## Requirements

- Per WG tunnel: `/etc/wireguard/<wg-name>.conf` (e.g. from wg-easy), with `PersistentKeepalive = 25`
- WireGuard kernel module on the host (kernel ≥ 5.6)

## Build

`docker compose` builds the image:

```bash
docker compose build
```

### Multi-arch (amd64 + arm64)

With `buildx` (create the builder once):

```bash
docker buildx create --name multiarch --use   # one-time

docker buildx build --platform linux/amd64,linux/arm64 \
  -t <registry>/wg-tunneld:latest --push ./build
```

> The base image `debian:bookworm-slim` and all packages are available for **amd64** and
> **arm64** — the Dockerfile is architecture-independent.

## Start

```bash
docker compose up -d
docker compose logs -f wg-tunneld  # check tunnel setup
```

Expected: one line `[wg] Tunnel '<name>' active.` per `<name>.conf`. Verify on the host:

```bash
wg show            # active tunnels + handshakes
ip link show       # one interface per <name>.conf
```

## Configuration

| Variable      | Default          | Meaning                                      |
|---------------|------------------|----------------------------------------------|
| `WG_CONF_DIR` | `/etc/wireguard` | Directory with the flat `<wg-name>.conf`     |

## Good to know

- **Host networking:** `wg-tunneld` creates the wg interfaces (each interface = file name
  `<wg-name>.conf` under `/etc/wireguard`) in the host namespace; the host and other
  host-networked containers share them.
- **15-char limit (IFNAMSIZ):** the interface name = file name without `.conf`. Files with a
  basename > 15 characters are skipped with `WARN` (read-only mount → no renaming).
- **Reboot resilience:** `wg-reresolve.sh` runs every minute via cron and re-resolves DynDNS
  endpoints after a node/server reboot.
- **Routing other containers through the tunnels:** a *non* host-networked (bridge) container
  routes through the host as gateway. `wg-tunneld` already sets `ip_forward`. Additionally one
  NAT rule per tunnel is needed so replies find their way back:
  `iptables -t nat -A POSTROUTING -o <wg-iface> -j MASQUERADE`.

## Files

```
build/                    # WireGuard image
├── Dockerfile
├── entrypoint-wg.sh      # sysctls + wg-quick + wg-reresolve watchdog (cron)
└── wg-reresolve.sh       # WireGuard watchdog
```

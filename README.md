# Sinbar

A keyboard-first [sing-box](https://sing-box.sagernet.org) tray plugin for the Omarchy Quattro bar. It surfaces live traffic, outbound groups, active connections, logs, and Clash mode switching in a compact bar panel, with an optional right-click shortcut to your own terminal TUI.

## Features

- Live download rate in the bar; upload/download rates and totals in the panel
- sing-box service, version, memory, goroutine, connection, and uptime status
- Select outbound nodes and run URL tests
- Switch Clash modes
- View sing-box Tailscale endpoint identity and peers, copy peer IPs, send files with Taildrop, and select or clear an Exit Node
- Drag files onto the bar item to send them to a Tailscale peer with Taildrop
- See the files other devices sent you with Taildrop, open one to look at it, save it to `~/Downloads`, or discard it
- Open the Tailscale authentication link when the endpoint needs login
- Inspect and close active connections
- Follow, filter, and clear sing-box logs, with sing-box's own log colors rendered instead of raw ANSI codes
- Mouse controls and TUI-style keyboard navigation
- Right-click the bar item to open a configurable TUI command in the terminal

Sinbar talks to the sing-box `StartedService` gRPC API through a small Go bridge. Tailscale status, Exit Node changes, and logout support use the same gRPC service directly—no native `tailscaled` or `tailscale` CLI is required. QML never receives the API secret.

<img src="docs/screenshot-tailscale.png" alt="The Tailscale tab, listing the endpoint identity, received Taildrop files, and peers" width="452">

## Requirements

- Omarchy Quattro shell
- [sing-box](https://sing-box.sagernet.org) with the `StartedService` gRPC API enabled
- A Nerd Font for the intended icons
- Optional: Go 1.25 or newer — only to build the bridge from source (no prebuilt
  binary for your CPU architecture, or you'd rather build locally)
- Optional: a terminal TUI command on `PATH` for the right-click action (configurable, disabled by default)

## Configuration

Sinbar reads its config from:

```toml
# ~/.config/sinbar/config.toml
host = "127.0.0.1"
port = 9999
secret = "your-api-secret"
tls = false
interval_ms = 1000
tailscale_endpoint = "Tailscale"
```

| Field | Meaning |
|---|---|
| `host` / `port` | Address sing-box's `StartedService` gRPC API listens on |
| `secret` | Auth secret for that API, if you configured one |
| `tls` | Whether the gRPC connection should use TLS |
| `interval_ms` | How often the bridge polls for status updates |
| `tailscale_endpoint` | Tailscale endpoint tag to display and control; defaults to `Tailscale` |

These must match whatever you configured in sing-box, not the other way around. If the file
doesn't exist, Sinbar falls back to `127.0.0.1:9999`, no secret, and a 1000ms interval — only
create the file if you need different values.

The bar settings expose:

- **Config path** — defaults to `~/.config/sinbar/config.toml`
- **Show live speeds in bar** — `On` or `Off`
- **TUI command** — empty by default; set it to any terminal TUI you want the right-click action to open

Keep the config file user-readable only when it contains a secret:

```sh
chmod 600 ~/.config/sinbar/config.toml
```

## Install

### Via the plugin marketplace / `omarchy plugin add`

```sh
omarchy plugin add https://github.com/d3vw/sinbar.git --enable
```

This just clones the repo and enables the widget — no separate build step. The first time
the plugin starts it downloads the prebuilt `sinbar-bridge` matching the installed version
from this repository's GitHub Releases and verifies its SHA-256; if a Go toolchain is on
`PATH` it builds from source instead. The binary is cached in `bin/sinbar-bridge` and
reused after that, and re-fetched when `omarchy plugin update` bumps the version.

### From a local checkout

```sh
make install-local
```

This builds `bin/sinbar-bridge`, validates the plugin, copies the runtime files to:

```text
~/.config/omarchy/plugins/io.github.d3vw.sinbar/
```

and enables the bar widget. Source edits do not automatically sync from this repository; rerun `make install-local` after changes.

To build without installing:

```sh
make check
```

## Uninstall

```sh
omarchy plugin remove io.github.d3vw.sinbar
```

From a local checkout, `make uninstall-local` runs the same command.

## Controls

| Input | Action |
|---|---|
| Left click | Open or close panel |
| Right click | Open the configured TUI command |
| Middle click | Restart the API bridge |
| Drag & drop files | Open the Tailscale tab to pick a peer, then Taildrop the files to it |
| Click a received file | Open it with the desktop's default application |
| `1` / `2` / `3` / `4` | Routes / Connections / Logs / Tailscale |
| `h` / `l` | Previous / next tab |
| `j` / `k` | Move selection |
| `Enter` | Select route; on Connections, close selected connection |
| `u` | URL-test selected route |
| `m` | Cycle Clash mode |
| `d` / `D` | Close selected / all connections |
| `c` | Clear logs |
| `/` | Filter logs by keyword (Logs tab); `Enter` confirms, `Esc` clears and exits |
| `r` | Reconnect bridge |
| `t` | Open TUI |
| `Esc` | Close panel |

## Development

The runtime files are:

```text
manifest.json          Plugin contract and settings
Panel.qml              Bar item and keyboard-driven popup
Service.qml            Bridge process, stream state, and actions
Model.js                Formatting helpers
cmd/sinbar-bridge/      JSON-lines gRPC bridge
client/                 sing-box StartedService API client
daemon/                 Generated StartedService protobuf bindings
```

Useful checks:

```sh
go test ./...
omarchy plugin validate "$PWD"
qmllint -I "$OMARCHY_PATH/shell" Panel.qml Service.qml
```

Inspect shell errors with:

```sh
qs log -p "$OMARCHY_PATH/shell" --tail 100
```

## Security

Omarchy plugins execute unsandboxed inside the long-running shell process. On first start Sinbar downloads the prebuilt `sinbar-bridge` matching the installed version from this repository's GitHub Releases, verifies its SHA-256 (and build-provenance attestation) before caching it, and builds from source instead when a Go toolchain is present. Beyond that it makes no network access, needs no elevated privileges, and runs no install hooks. That is a smaller, fixed, reproducible attack surface than a first-run `go build` pulling dozens of transitive module dependencies. The bridge reads the configured secret directly from the TOML file and does not place it in process arguments or QML state.

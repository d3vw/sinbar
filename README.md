# Sinbar

A keyboard-first [sing-box](https://sing-box.sagernet.org) tray plugin for the Omarchy Quattro bar. It surfaces live traffic, outbound groups, active connections, logs, and Clash mode switching in a compact bar panel, with an optional right-click shortcut to your own terminal TUI.

## Features

- Live upload/download rates and totals in the bar and panel
- sing-box service, version, memory, goroutine, connection, and uptime status
- Select outbound nodes and run URL tests
- Switch Clash modes
- Inspect and close active connections
- Follow, filter, and clear sing-box logs, with sing-box's own log colors rendered instead of raw ANSI codes
- Mouse controls and TUI-style keyboard navigation
- Right-click the bar item to open a configurable TUI command in the terminal

Sinbar talks to the sing-box `StartedService` gRPC API through a small Go bridge. QML never receives the API secret.

## Requirements

- Omarchy Quattro shell
- [sing-box](https://sing-box.sagernet.org) with the `StartedService` gRPC API enabled
- Go 1.25 or newer to build the bridge
- A Nerd Font for the intended icons
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
```

| Field | Meaning |
|---|---|
| `host` / `port` | Address sing-box's `StartedService` gRPC API listens on |
| `secret` | Auth secret for that API, if you configured one |
| `tls` | Whether the gRPC connection should use TLS |
| `interval_ms` | How often the bridge polls for status updates |

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

This just clones the repo and enables the widget — no separate build step. The Go bridge
(`bin/sinbar-bridge`) is built automatically from source the first time the plugin starts,
so a Go toolchain must be on `PATH`. Startup takes a few extra seconds on that first run
while it compiles; after that the built binary is reused.

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
| `1` / `2` / `3` | Routes / Connections / Logs |
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

Omarchy plugins execute unsandboxed inside the long-running shell process. Sinbar starts only its bundled bridge and explicit user actions, with no elevated privileges, install hooks, or remote downloads. The bridge reads the configured secret directly from the TOML file and does not place it in process arguments or QML state.

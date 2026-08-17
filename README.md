# Sinbar

A keyboard-first sing-box tray plugin for the Omarchy Quattro bar. It brings the useful parts of `lazy-box`—live traffic, outbound groups, active connections, logs, and Clash mode switching—into a compact bar panel while keeping the full TUI one right-click away.

## Features

- Live upload/download rates and totals in the bar and panel
- sing-box service, version, memory, goroutine, connection, and uptime status
- Select outbound nodes and run URL tests
- Switch Clash modes
- Inspect and close active connections
- Follow, filter, and clear sing-box logs, with sing-box's own log colors rendered instead of raw ANSI codes
- Mouse controls and TUI-style keyboard navigation
- Right-click the bar item to open `lazy-box` in the configured terminal

Sinbar talks to the sing-box `StartedService` gRPC API through a small Go bridge. The bridge is based on the client and protobuf contract from `lazy-box`; QML never receives the API secret.

## Requirements

- Omarchy Quattro shell
- sing-box with the `StartedService` gRPC API enabled
- Go 1.25 or newer to build the bridge
- A Nerd Font for the intended icons
- Optional: `lazy-box` on `PATH` for the right-click TUI action

## Configuration

Sinbar reads the same config as `lazy-box` by default:

```toml
# ~/.config/lazy-box/config.toml
host = "127.0.0.1"
port = 9999
secret = "your-api-secret"
tls = false
interval_ms = 1000
```

The bar settings expose:

- **lazy-box config path** — defaults to `~/.config/lazy-box/config.toml`
- **Show live speeds in bar** — `On` or `Off`
- **TUI command** — defaults to `lazy-box`

Keep the config file user-readable only when it contains a secret:

```sh
chmod 600 ~/.config/lazy-box/config.toml
```

## Build and install locally

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

To remove the local installation:

```sh
make uninstall-local
```

## Controls

| Input | Action |
|---|---|
| Left click | Open or close panel |
| Right click | Open the full `lazy-box` TUI |
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
client/                 API client derived from lazy-box
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

Omarchy plugins execute unsandboxed inside the long-running shell process. Sinbar starts only its bundled bridge and explicit user actions. It does not use `sudo`, install hooks, or remote downloads. The bridge reads the configured secret directly from the TOML file and does not place it in process arguments or QML state.

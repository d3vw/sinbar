# Sinbar Project Instructions

## Project Scope

Sinbar is an Omarchy Quattro bar plugin that monitors and controls sing-box through the `StartedService` gRPC API.

## Architecture

- Keep the bar widget and panel UI in QML.
- Use the Go JSON-lines bridge for all gRPC communication.
- Read connection settings from `~/.config/sinbar/config.toml` by default.
- Never expose the API secret in QML state, logs, command-line arguments, or screenshots.
- Keep high-frequency connection and log streams active only while the panel is open.

## UI Requirements

- Preserve a fixed-width bar layout so speed changes never resize the module.
- Keep the icon and both speed readouts inside one continuous click target.
- Draw the open-panel indicator across the complete clickable area.
- Use the `📦` glyph as the Sinbar icon.
- Keep keyboard navigation consistent with terminal and TUI conventions.
- Preserve support for left click, middle click, and right click behavior.

## Installation Rules

- Never modify files under `$OMARCHY_PATH/shell/plugins/`.
- Install the user plugin under `~/.config/omarchy/plugins/io.github.d3vw.sinbar/`.
- Use `make install-local` for local installation.
- Keep bridge installation atomic to avoid `Text file busy` errors.

## Development Workflow

- Inspect existing code before changing behavior.
- Keep changes focused and avoid unrelated refactors.
- Reuse existing helpers and components instead of duplicating logic.
- Update `README.md` when configuration, controls, installation, or user-visible behavior changes.
- Do not commit secrets, generated binaries, screenshots, or temporary files.

## Validation

Run these checks after relevant changes:

```bash
qmllint -I "$OMARCHY_PATH/shell" Panel.qml Service.qml
omarchy plugin validate .
go test ./...
make install-local
```

Restart the shell when QML hot reload does not reliably replace existing plugin instances:

```bash
omarchy restart shell
```

Ignore the unrelated host portal registration warning unless it causes an observable failure.

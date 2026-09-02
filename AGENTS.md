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
- Keep the icon and the bar speed readout (download only) inside one continuous click target.
- Draw the open-panel indicator across the complete clickable area.
- Use the `󰏗` Nerd Font glyph as the Sinbar icon so it inherits the bar's theme color.
- Keep keyboard navigation consistent with terminal and TUI conventions.
- Preserve support for left click, middle click, and right click behavior.

## Installation Rules

- Never modify files under `$OMARCHY_PATH/shell/plugins/`.
- Install the user plugin under `~/.config/omarchy/plugins/io.github.d3vw.sinbar/`.
- Use `make install-local` for local installation.
- Keep bridge installation atomic to avoid `Text file busy` errors.
- `omarchy plugin add` only git-clones the repo; it never runs a build step. `bridgeCommand()`
  in Service.qml runs `scripts/ensure-bridge.sh`, which on first run (and after `omarchy plugin
  update` changes `manifest.json`'s version) downloads the prebuilt bridge for the arch from the
  matching GitHub Release, verifies its SHA-256, falls back to `go build` when Go is present, and
  otherwise errors. `bin/.version` stamps which manifest version the staged binary was built for.
- Keep the release workflow (`.github/workflows/release.yml`) able to produce
  `sinbar-bridge-linux-<amd64|arm64>` plus `.sha256` assets: bump `manifest.json`'s version, then
  push a matching `vX.Y.Z` tag. The tag/version check in that workflow is intentional.
- `make install-local` must keep copying `scripts/ensure-bridge.sh` into the plugin dir and
  writing `bin/.version`, or a locally built bridge gets discarded and re-downloaded on first run.

## Development Workflow

- Inspect existing code before changing behavior.
- Keep changes focused and avoid unrelated refactors.
- Reuse existing helpers and components instead of duplicating logic.
- Update `README.md` when configuration, controls, installation, or user-visible behavior changes.
- Do not commit secrets, generated binaries, or temporary files. The root `preview.png` and
  the screenshots under `docs/` are deliberate listing and documentation assets; incidental
  screenshots still do not belong in the repository.

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

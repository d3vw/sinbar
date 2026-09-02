#!/bin/sh
# Make sure bin/sinbar-bridge exists, then exec it with the given arguments.
#
# `omarchy plugin add` only git-clones this repo; nothing builds the bridge.
# On first run -- and again after `omarchy plugin update` bumps the version --
# this script, in order:
#
#   1. downloads the prebuilt bridge for this CPU architecture from the GitHub
#      Release matching manifest.json's version and verifies its SHA-256, else
#   2. builds it from source when a Go toolchain is on PATH, else
#   3. exits with an explanation of what to install.
#
# The bin/.version stamp records which manifest version the staged binary was
# produced for, so a plain clone self-heals on the next launch after an update.
set -eu

PLUGIN_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BIN="$PLUGIN_DIR/bin/sinbar-bridge"
STAMP="$PLUGIN_DIR/bin/.version"
REPO="d3vw/sinbar"

VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$PLUGIN_DIR/manifest.json" | head -n1)

need_fetch() {
  [ -x "$BIN" ] || return 0
  [ "$(cat "$STAMP" 2>/dev/null || true)" = "$VERSION" ] || return 0
  return 1
}

build_from_source() {
  command -v go >/dev/null 2>&1 || return 1
  ( cd "$PLUGIN_DIR" &&
    go build -trimpath -ldflags='-s -w' -o "$BIN" ./cmd/sinbar-bridge )
}

if need_fetch; then
  mkdir -p "$PLUGIN_DIR/bin"

  case "$(uname -m)" in
    x86_64)  arch=amd64 ;;
    aarch64) arch=arm64 ;;
    *)       arch= ;;
  esac

  tmp="$PLUGIN_DIR/bin/.sinbar-bridge.$$"
  fetched=0

  if [ -n "$VERSION" ] && [ -n "$arch" ]; then
    base="https://github.com/$REPO/releases/download/v$VERSION"
    asset="sinbar-bridge-linux-$arch"
    if curl -fsSL "$base/$asset" -o "$tmp" &&
       curl -fsSL "$base/$asset.sha256" -o "$tmp.sha256"; then
      expected=$(cut -d' ' -f1 "$tmp.sha256")
      actual=$(sha256sum "$tmp" | cut -d' ' -f1)
      if [ -n "$expected" ] && [ "$expected" = "$actual" ]; then
        chmod 755 "$tmp"
        mv -f "$tmp" "$BIN"
        fetched=1
      fi
    fi
  fi
  rm -f "$tmp" "$tmp.sha256"

  if [ "$fetched" -eq 1 ]; then
    printf '%s' "$VERSION" > "$STAMP"
  elif build_from_source; then
    printf '%s' "$VERSION" > "$STAMP"
  elif [ -x "$BIN" ]; then
    # An upgrade couldn't be fetched or built, but the previously staged
    # binary is still here -- keep the widget working and just warn.
    echo "sinbar: could not update the bridge to v$VERSION (no download, no Go); using the existing binary." >&2
  else
    echo "sinbar: no prebuilt bridge for $(uname -m) at v$VERSION, and no Go toolchain found." >&2
    echo "        Install Go (pacman -S go) or run 'make install-local' from a checkout." >&2
    exit 1
  fi
fi

exec "$BIN" "$@"

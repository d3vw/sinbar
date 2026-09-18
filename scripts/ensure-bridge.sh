#!/bin/sh
# Start the bridge, preparing a matching version when necessary.
#
# Bootstrap files must not be created inside the plugin directory: Quickshell
# watches that directory and would reload the plugin while a download is in
# progress. Downloaded and fallback-built bridges therefore live in the user
# cache. Locally installed bridges remain supported in bin/.
set -eu

PLUGIN_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PLUGIN_BRIDGE="$PLUGIN_DIR/bin/sinbar-bridge"
STAMP="$PLUGIN_DIR/bin/.version"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/sinbar/bridges"
REPO="d3vw/sinbar"

VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$PLUGIN_DIR/manifest.json" | head -n1)

case "$(uname -m)" in
  x86_64)  arch=amd64 ;;
  aarch64) arch=arm64 ;;
  *)       arch= ;;
esac

need_fetch() {
  [ -x "$PLUGIN_BRIDGE" ] || return 0
  [ "$(cat "$STAMP" 2>/dev/null || true)" = "$VERSION" ] || return 0
  return 1
}

if ! need_fetch; then
  exec "$PLUGIN_BRIDGE" "$@"
fi

CACHED_BRIDGE="$CACHE_DIR/sinbar-bridge-$VERSION-$arch"
if [ -n "$VERSION" ] && [ -n "$arch" ] && [ -x "$CACHED_BRIDGE" ]; then
  exec "$CACHED_BRIDGE" "$@"
fi

mkdir -p "$CACHE_DIR"
tmp="$CACHE_DIR/.sinbar-bridge.$$"
trap 'rm -f "$tmp" "$tmp.sha256"' EXIT HUP INT TERM
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
      mv -f "$tmp" "$CACHED_BRIDGE"
      fetched=1
    fi
  fi
fi

if [ "$fetched" -eq 1 ]; then
  rm -f "$tmp.sha256"
  exec "$CACHED_BRIDGE" "$@"
fi

if command -v go >/dev/null 2>&1 &&
   ( cd "$PLUGIN_DIR" &&
     go build -trimpath -ldflags='-s -w' -o "$tmp" ./cmd/sinbar-bridge ); then
  chmod 755 "$tmp"
  mv -f "$tmp" "$CACHED_BRIDGE"
  rm -f "$tmp.sha256"
  exec "$CACHED_BRIDGE" "$@"
fi

if [ -x "$PLUGIN_BRIDGE" ]; then
  # An upgrade couldn't be fetched or built, but the previously staged binary
  # is still here -- keep the widget working and just warn.
  echo "sinbar: could not update the bridge to v$VERSION (no download, no Go); using the existing binary." >&2
  exec "$PLUGIN_BRIDGE" "$@"
fi

echo "sinbar: no prebuilt bridge for $(uname -m) at v$VERSION, and no Go toolchain found." >&2
echo "        Install Go (pacman -S go) or run 'make install-local' from a checkout." >&2
exit 1

#!/usr/bin/env bash
# Builds the uPlayer Linux desktop bundle.
#
#   scripts/build_linux.sh [debug|release]   (default: release)
#
# Steps:
#   1. compile the Go sidecar (go_backend/cmd/uplayer_sidecar) — the Linux
#      stand-in for Android's gomobile AAR,
#   2. build the Flutter Linux bundle,
#   3. copy the sidecar next to the app executable, where
#      `LinuxGoTransport` looks for it at runtime.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILD_MODE="${1:-release}"
case "$BUILD_MODE" in
  debug|release|profile) ;;
  *) echo "usage: $0 [debug|release|profile]" >&2; exit 2 ;;
esac

# Flutter is not necessarily on PATH (Omarchy keeps it under
# ~/development/flutter by default).
FLUTTER_BIN="${FLUTTER_BIN:-}"
if [ -z "$FLUTTER_BIN" ]; then
  if command -v flutter >/dev/null 2>&1; then
    FLUTTER_BIN="$(command -v flutter)"
  else
    for candidate in "$HOME/development/flutter/bin/flutter" \
                     "$HOME/flutter/bin/flutter" \
                     "/opt/flutter/bin/flutter"; do
      if [ -x "$candidate" ]; then FLUTTER_BIN="$candidate"; break; fi
    done
  fi
fi
if [ -z "$FLUTTER_BIN" ]; then
  echo "flutter not found; set FLUTTER_BIN=/path/to/flutter" >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64|amd64) ARCH_DIR="x64" ;;
  aarch64|arm64) ARCH_DIR="arm64" ;;
  armv7l|arm) ARCH_DIR="arm" ;;
  *) ARCH_DIR="$(uname -m)" ;;
esac

echo "==> Building Go sidecar"
mkdir -p build/go_sidecar
(
  cd go_backend
  go build -trimpath -o ../build/go_sidecar/uplayer_go_sidecar ./cmd/uplayer_sidecar
)

echo "==> Building Flutter Linux bundle ($BUILD_MODE)"
"$FLUTTER_BIN" build linux --"$BUILD_MODE"

BUNDLE_DIR="build/linux/$ARCH_DIR/$BUILD_MODE/bundle"
if [ ! -x "$BUNDLE_DIR/u_player" ]; then
  echo "bundle not found at $BUNDLE_DIR (did the Flutter build succeed?)" >&2
  exit 1
fi

cp build/go_sidecar/uplayer_go_sidecar "$BUNDLE_DIR/"
chmod +x "$BUNDLE_DIR/uplayer_go_sidecar"

echo
echo "==> Done"
echo "    bundle:  $BUNDLE_DIR"
echo "    run it:  $BUNDLE_DIR/u_player"

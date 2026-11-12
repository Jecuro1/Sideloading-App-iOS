#!/usr/bin/env bash
# Starts the built app in demo mode for several scenarios and captures the window.
# Usage: ./Scripts/screenshots.sh   (after ./Scripts/build-app.sh)
set -uo pipefail

cd "$(dirname "$0")/.."
BIN="build/IPA Beam.app/Contents/MacOS/IPABeam"
OUT="screenshots"
mkdir -p "$OUT"

for scenario in ${SCENARIOS:-ready installing success drop idle failed}; do
  WINFILE="$(mktemp -t ipabeam)"
  rm -f "$WINFILE"

  IPABEAM_DEMO="$scenario" IPABEAM_WINDOW_FILE="$WINFILE" "$BIN" >/dev/null 2>&1 &
  PID=$!

  for _ in $(seq 1 60); do
    [ -s "$WINFILE" ] && break
    sleep 0.5
  done
  sleep 2

  if [ -s "$WINFILE" ]; then
    screencapture -x -o -l"$(cat "$WINFILE")" "$OUT/$scenario.png" || echo "window capture failed for $scenario"
  else
    echo "no window id for $scenario"
  fi
  [ -s "$OUT/$scenario.png" ] || screencapture -x "$OUT/$scenario-screen.png"

  kill "$PID" 2>/dev/null
  wait "$PID" 2>/dev/null
  echo "✓ $scenario"
done

ls -la "$OUT"

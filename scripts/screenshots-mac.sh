#!/usr/bin/env bash
# Captures the Mac README screenshots of the example app.
# Usage: scripts/screenshots-mac.sh <Scheme> <scene> [<scene> ...]
# Writes docs/screenshots/mac-<scene>.png, for example mac-browse.png, and fails instead of
# saving a blank or broken capture.
#
# Launched with `-screenshot <scene>`, the app opens a 1440 x 900 window on a fixed scene, loads
# live stations from the Radio Browser API and their real favicons, and writes
# the file given with `-screenshot-ready-file` once the data and every image on screen are loaded.
#
# 1. Preferred: `screencapture -l <window id>` of the window, with the id looked up by
#    scripts/window-id.swift (CGWindowListCopyWindowInfo, filtered by the app's process id).
# 2. Fallback: `-render-screenshot <file>` makes the app draw its window into a PNG itself
#    (NSView.cacheDisplay at 2x) once the scene is ready, and quit. It needs no Screen Recording
#    permission. It shows the same live scene; it only runs when 1 fails. It may not draw the
#    translucent sidebar of macOS 26 (cacheDisplay can leave it a blank white panel; the app gives
#    its sidebar an opaque background for that reason) and leaves out
#    the title bar, so 1 is what the README should show.
set -euo pipefail

SCHEME="$1"; shift
PROJECT="Example/RadioBrowserDemo.xcodeproj"
OUT="docs/screenshots"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

MIN_BYTES=100000  # a window without favicons compresses to far less
# pixels. The window is 1440 points wide, or the width of the screen when that is smaller: the
# macos-26 runner has a 1024 x 768 display at 1x, so its captures are 1024 pixels wide.
MIN_WIDTH=960

xcrun swiftc -O scripts/window-id.swift -o "$TMP/window-id"

xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= | tail -n 5

APP="$(find build/Build/Products -maxdepth 2 -name "$SCHEME.app" | head -n 1)"
BIN="$APP/Contents/MacOS/$SCHEME"
if [ -z "$APP" ] || [ ! -x "$BIN" ]; then
  echo "Could not find $SCHEME.app in build/Build/Products" >&2
  exit 1
fi

# valid_capture <file> <previous capture or empty>
# Rejects missing, small or narrow PNGs, and a capture identical to the previous scene.
valid_capture() {
  local file="$1" previous="$2" width
  local bytes
  if [ ! -s "$file" ]; then echo "  rejected: no file"; return 1; fi
  bytes="$(wc -c < "$file" | tr -d ' ')"
  width="$(sips -g pixelWidth "$file" 2>/dev/null | awk '/pixelWidth/ { print $2 }')"
  echo "  capture: ${width:-?} pixels wide, $bytes bytes"
  [ "$bytes" -gt "$MIN_BYTES" ] || { echo "  rejected: too small"; return 1; }
  [ -n "$width" ] && [ "$width" -ge "$MIN_WIDTH" ] || { echo "  rejected: too narrow"; return 1; }
  if [ -n "$previous" ] && cmp -s "$file" "$previous"; then
    echo "  rejected: same as the previous scene"
    return 1
  fi
  return 0
}

# wait_for_ready <pid> <marker> <seconds>: waits until the app writes the marker. Fails when the
# app quits or the time runs out.
wait_for_ready() {
  local pid="$1" marker="$2" limit="$3" waited=0
  while [ ! -f "$marker" ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "The app quit before the scene was ready"
      return 1
    fi
    if [ "$waited" -ge "$limit" ]; then
      echo "The scene was not ready after $limit seconds"
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
}

# wait_for_exit <pid> <seconds>: waits for the process to quit, kills it after the timeout.
# Returns the process's exit status, or 124 on a timeout.
wait_for_exit() {
  local pid="$1" limit="$2" waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$limit" ]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid"
}

# -ApplePersistenceIgnoreState keeps macOS from restoring windows of an earlier run.

# capture_window <scene> <file>: the preferred path, screencapture of the app's window by its id.
capture_window() {
  local scene="$1" file="$2" pid id marker="$TMP/ready-$scene"
  rm -f "$marker"
  "$BIN" -screenshot "$scene" -screenshot-ready-file "$marker" -ApplePersistenceIgnoreState YES \
    > "$TMP/$scene-window.log" 2>&1 &
  pid=$!
  if wait_for_ready "$pid" "$marker" 150; then
    # Let images fade in.
    sleep 3
    id="$("$TMP/window-id" "$pid" || true)"
    if [ -n "$id" ]; then
      echo "  window $id"
      screencapture -x -o -l "$id" "$file" || echo "  screencapture exited with $?"
    else
      echo "No window found for $scene"
    fi
  else
    tail -n 20 "$TMP/$scene-window.log" || true
  fi
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

# render <scene> <file>: the fallback, the app renders its own window once the scene is ready.
render() {
  local scene="$1" file="$2" pid status=0
  "$BIN" -screenshot "$scene" -screenshot-ready-file "$TMP/render-ready-$scene" -render-screenshot "$file" \
    -ApplePersistenceIgnoreState YES > "$TMP/$scene.log" 2>&1 &
  pid=$!
  wait_for_exit "$pid" 180 || status=$?
  tail -n 20 "$TMP/$scene.log" || true
  return "$status"
}

previous=""
for scene in "$@"; do
  capture="$TMP/$scene.png"
  ok=0
  for attempt in 1 2; do
    rm -f "$capture"
    capture_window "$scene" "$capture"
    if valid_capture "$capture" "$previous"; then
      ok=1
      break
    fi
    echo "screencapture of $scene failed or was blank (attempt $attempt)"
  done
  if [ "$ok" -ne 1 ]; then
    echo "Falling back to the app's own renderer for $scene"
    rm -f "$capture"
    if render "$scene" "$capture" && valid_capture "$capture" "$previous"; then
      ok=1
    fi
  fi
  if [ "$ok" -ne 1 ]; then
    echo "Capture for mac-$scene is still blank or missing; refusing to commit a broken screenshot." >&2
    exit 1
  fi
  mv "$capture" "$OUT/mac-$scene.png"
  previous="$OUT/mac-$scene.png"
  echo "Captured $previous ($(wc -c < "$previous" | tr -d ' ') bytes)"
done

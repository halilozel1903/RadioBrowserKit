#!/usr/bin/env bash
# Captures README screenshots of the example apps on an Apple TV and an iPhone simulator.
# Usage: scripts/screenshots.sh <project> --tv <Scheme> <bundle id> <scene> [<scene> ...] \
#                                         --iphone <Scheme> <bundle id> <scene> [<scene> ...]
# Writes docs/screenshots/<device>-<scene>.png, for example tv-home.png and tv-nowplaying.png.
# Each app writes tmp/screenshot-ready into its container once the scene is on screen; the script
# waits for that marker and exits with an error instead of keeping a blank, stale or home-screen
# capture.
set -euo pipefail

PROJECT="$1"; shift
TV_SCHEME=""; TV_BUNDLE=""; TV_SCENES=()
PHONE_SCHEME=""; PHONE_BUNDLE=""; PHONE_SCENES=()
target=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tv)
      target=tv; TV_SCHEME="$2"; TV_BUNDLE="$3"; shift 3; continue ;;
    --iphone)
      target=iphone; PHONE_SCHEME="$2"; PHONE_BUNDLE="$3"; shift 3; continue ;;
    *)
      case "$target" in
        tv) TV_SCENES+=("$1") ;;
        iphone) PHONE_SCENES+=("$1") ;;
        *) echo "Scene $1 must follow --tv or --iphone" >&2; exit 1 ;;
      esac
      ;;
  esac
  shift
done
if [ ${#TV_SCENES[@]} -eq 0 ] && [ ${#PHONE_SCENES[@]} -eq 0 ]; then
  echo "No scenes given" >&2
  exit 1
fi
OUT="docs/screenshots"
MIN_BYTES=100000
mkdir -p "$OUT"

# newest_runtime <platform regex>: identifier of the newest available runtime, or nothing.
newest_runtime() {
  xcrun simctl list runtimes available -j | jq -r --arg platform "$1" '
    [.runtimes[] | select(.identifier | test($platform))]
    | sort_by(.version | split(".") | map(tonumber)) | last | .identifier // empty'
}

# pick_device <runtime regex> <device family regex> <preferred name pattern> ...
# Prints the UDID of an available simulator on the newest matching runtime, preferring the first
# name pattern that matches. Creates one when none exists.
pick_device() {
  local platform="$1" family="$2"; shift 2
  local devices udid pattern type runtime
  devices=$(xcrun simctl list devices available -j | jq -c --arg platform "$platform" --arg family "$family" '
    [.devices | to_entries | sort_by(.key) | reverse | .[]
     | select(.key | test($platform)) | .value[] | select(.name | test($family))]')
  for pattern in "$@"; do
    udid=$(jq -r --arg pattern "$pattern" 'map(select(.name | test($pattern))) | .[0].udid // empty' <<< "$devices")
    if [ -n "$udid" ]; then echo "$udid"; return; fi
  done
  udid=$(jq -r '.[0].udid // empty' <<< "$devices")
  if [ -z "$udid" ]; then
    runtime=$(newest_runtime "$platform")
    type=$(xcrun simctl list devicetypes -j | jq -r --arg family "$family" --arg preferred "${1:-}" '
      [.devicetypes[] | select(.name | test($family))]
      | (map(select(.name | test($preferred))) + .) | .[0].identifier // empty')
    if [ -z "$type" ] || [ -z "$runtime" ]; then
      echo "No $family simulator, device type or runtime available" >&2
      exit 1
    fi
    udid=$(xcrun simctl create "Screenshots $family" "$type" "$runtime")
  fi
  echo "$udid"
}

# build <scheme> <udid>: builds the scheme for the simulator and prints the app's path.
build() {
  local scheme="$1" udid="$2" app
  xcodebuild build \
    -project "Example/$PROJECT.xcodeproj" \
    -scheme "$scheme" \
    -destination "id=$udid" \
    -derivedDataPath build \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= | tail -n 5 >&2
  app=$(find build/Build/Products -maxdepth 2 -name "$scheme.app" | head -n 1)
  if [ -z "$app" ]; then
    echo "Build product $scheme.app not found" >&2
    exit 1
  fi
  echo "$app"
}

# valid_capture <file> <previous capture or empty>
# A blank frame (app still launching) compresses to a tiny PNG, and a capture identical to the
# previous scene means the app never switched scenes.
valid_capture() {
  local file="$1" previous="$2"
  [ -s "$file" ] || return 1
  [ "$(wc -c < "$file")" -gt "$MIN_BYTES" ] || return 1
  sips -g pixelWidth "$file" > /dev/null 2>&1 || return 1
  if [ -n "$previous" ] && cmp -s "$file" "$previous"; then
    return 1
  fi
  return 0
}

# capture <udid> <app> <bundle id> <device label> <scene> [<scene> ...]: boots the simulator,
# captures every scene, shuts it down again, so `booted` always means this one simulator.
capture() {
  local udid="$1" app="$2" bundle="$3" device="$4" scene file previous="" attempt ok waited
  shift 4
  local scenes=("$@")
  xcrun simctl shutdown all > /dev/null 2>&1 || true
  xcrun simctl boot "$udid" || true
  xcrun simctl bootstatus "$udid" -b
  if [ "$device" = "iphone" ]; then
    xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
    xcrun simctl ui "$udid" appearance dark
  fi
  xcrun simctl install "$udid" "$app"
  local container home
  container=$(xcrun simctl get_app_container "$udid" "$bundle" data)
  # System banners (such as "Ready for Apple Intelligence") appear shortly after a first boot.
  # Launch the app once and let them come and go before capturing anything.
  xcrun simctl launch "$udid" "$bundle" > /dev/null 2>&1 || true
  sleep 45
  xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
  # Give the home screen time to settle, then keep a capture of it so a frame where the app never
  # came to the front is rejected.
  sleep 15
  home="$OUT/.home-$device.png"
  xcrun simctl io "$udid" screenshot "$home"

  for scene in "${scenes[@]}"; do
    file="$OUT/$device-$scene.png"
    ok=""
    for attempt in 1 2 3; do
      xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
      sleep 1
      rm -f "$container/tmp/screenshot-ready"
      if ! xcrun simctl launch "$udid" "$bundle" -screenshot "$scene"; then
        echo "Could not launch the app for $device-$scene (attempt $attempt), retrying"
        continue
      fi
      # The app writes this marker once the scene is on screen.
      waited=0
      while [ ! -f "$container/tmp/screenshot-ready" ] && [ "$waited" -lt 180 ]; do
        sleep 1
        waited=$((waited + 1))
      done
      if [ ! -f "$container/tmp/screenshot-ready" ]; then
        echo "The app did not show $scene on $device, retrying"
        continue
      fi
      # Let focus effects and transitions settle (tvOS is slower than iOS).
      sleep $((3 + attempt * 2))
      rm -f "$file"
      xcrun simctl io "$udid" screenshot "$file"
      if valid_capture "$file" "$previous" && ! cmp -s "$file" "$home"; then
        ok=1
        break
      fi
      echo "Blank or stale capture for $device-$scene, retrying"
    done
    if [ -z "$ok" ]; then
      echo "Capture for $device-$scene is still blank; refusing to commit a broken screenshot." >&2
      rm -f "$file" "$home"
      exit 1
    fi
    previous="$file"
    echo "Captured $file ($(wc -c < "$file") bytes)"
  done

  rm -f "$home"
  xcrun simctl shutdown "$udid" || true
}

if [ ${#TV_SCENES[@]} -gt 0 ]; then
  # A tvOS simulator runtime is needed to build and run; download it if the runner has none.
  if [ -z "$(newest_runtime tvOS)" ]; then
    echo "No tvOS simulator runtime installed, downloading one"
    xcodebuild -downloadPlatform tvOS
  fi
  TV=$(pick_device tvOS "^Apple TV" "^Apple TV 4K \\(3rd generation\\)$" "4K")
  echo "Using Apple TV simulator $TV"
  TV_APP=$(build "$TV_SCHEME" "$TV")
  capture "$TV" "$TV_APP" "$TV_BUNDLE" tv "${TV_SCENES[@]}"
fi

if [ ${#PHONE_SCENES[@]} -gt 0 ]; then
  IPHONE=$(pick_device "iOS" "^iPhone" "^iPhone [0-9]+ Pro$" "Pro$" "^iPhone [0-9]+$")
  echo "Using iPhone simulator $IPHONE"
  PHONE_APP=$(build "$PHONE_SCHEME" "$IPHONE")
  capture "$IPHONE" "$PHONE_APP" "$PHONE_BUNDLE" iphone "${PHONE_SCENES[@]}"
fi

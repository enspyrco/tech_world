#!/usr/bin/env bash
# Bring up two independent Tech World clients for live multiplayer verification.
#
# Client A: macOS, real account. The only place the native FFI capture path and
#           the Impeller shader path run.
# Client B: Chrome on an isolated --user-data-dir, guest sign-in. The separate
#           profile is what allows two identities at once; it is also the ONLY
#           place the Dreamfinder avatar bridge is real -- on native,
#           dreamfinder_avatar_bridge.dart exports a no-op stub whose isReady
#           is false forever, so onReady cannot fire there.
#
# Prints the web app's URL, which changes every run. Pointing a stale tab at the
# previous run's port is the failure this script exists to stop repeating.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RUN_DIR="${TMPDIR:-/tmp}/tech-world-two-clients"
mkdir -p "$RUN_DIR"
CHROME_PROFILE="$RUN_DIR/chrome-profile-guest"
CHROME_LOG="$RUN_DIR/chrome.log"
MACOS_APP="build/macos/Build/Products/Debug/tech_world.app"
MACOS_PROC="tech_world.app/Contents/MacOS/tech_world"

echo "==> Building + launching macOS client"
flutter build macos --debug >"$RUN_DIR/macos-build.log" 2>&1
open "$MACOS_APP"

# `open` exits 0 for a launch it merely dispatched, so confirm the process.
for _ in $(seq 1 20); do
  pgrep -f "$MACOS_PROC" >/dev/null && break
  sleep 1
done
if pgrep -f "$MACOS_PROC" >/dev/null; then
  echo "    macOS client up (pid $(pgrep -f "$MACOS_PROC" | head -1))"
else
  echo "    macOS client FAILED to start - see $RUN_DIR/macos-build.log" >&2
  exit 1
fi

echo "==> Launching Chrome guest client (isolated profile)"
flutter run -d chrome --web-browser-flag="--user-data-dir=$CHROME_PROFILE" \
  >"$CHROME_LOG" 2>&1 &

echo "==> Waiting for the web app to serve"
APP_URL=""
for _ in $(seq 1 90); do
  for port in $(lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null \
                | awk '/dart/ {split($9,a,":"); print a[length(a)]}' | sort -u); do
    if curl -s --max-time 2 "http://localhost:$port/" 2>/dev/null \
       | grep -qi "<title>Tech World"; then
      APP_URL="http://localhost:$port"
      break 2
    fi
  done
  sleep 2
done

if [ -z "$APP_URL" ]; then
  echo "    Web app never served - see $CHROME_LOG" >&2
  exit 1
fi

command -v pbcopy >/dev/null && printf '%s' "$APP_URL" | pbcopy
cat <<MSG

    Web app: $APP_URL  (copied to clipboard)
    Chrome log: $CHROME_LOG

Next, by hand:
  1. Chrome  -> "continue as guest", allow camera + mic
  2. macOS   -> create/enter a room; note its name
  3. Chrome  -> join that same room from the list
  4. Walk the avatars into OVERLAP (merge threshold is 96.0 centre-to-centre)

Read the results with:  tool/verify_av.sh
MSG

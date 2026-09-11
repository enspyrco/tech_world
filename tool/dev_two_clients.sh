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
# CAMERA: the Chrome guest publishes a SYNTHETIC video track by default
#           (--use-fake-device-for-media-stream). One machine has one webcam,
#           and the merge shader needs TWO camera-publishing participants --
#           `_local_player_` plus a remote -- because _videoBubbleIfPossible
#           gates on hasVideoTrack(participant). Without this the two clients
#           contend for the same device and the merge group can never reach 2,
#           which is why bubbles_merged has never once appeared in a log.
#           What this does NOT fake: the web capture path. A synthetic track
#           still goes through MediaStreamTrackProcessor -> VideoFrame ->
#           decodeImageFromPixels exactly as a real one does. Only the photons
#           are fake. Set REAL_CAMERA=1 to use the actual device instead.
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
# nohup + disown, NOT a bare `&`. A bare background job dies with its parent
# when the launcher's process group is torn down -- which is exactly what
# happened the first time this script ran: it printed a URL that was true when
# written and dead one second later.
# ── CORS/TLS dev proxy for the token path ────────────────────────────────────
# realm-token-server rejects every browser Origin with 403 "origin not allowed"
# (measured 2026-09-11 across 10 origins, prod domains included) and sends no
# Access-Control-* headers. Without a proxy the web client cannot obtain a
# LiveKit token AT ALL, which is why verify_av.sh's Concern 3 -- documented as
# Chrome-ONLY -- had never once been satisfiable.
#
# The proxy also has to serve HTTPS: FirebaseAuthProvider throws ArgumentError
# unless exchangeEndpoint is https (firebase_auth_provider.dart:47), and
# ArgumentError is an Error, so it escapes RealmTokenSource's Exception handlers
# and surfaces as "Token source threw unexpectedly".
#
# Set NO_CORS_PROXY=1 to skip it (web client will not be able to join a room).
PROXY_PORT="${CORS_PROXY_PORT:-8787}"
CHROME_TLS_FLAGS=()
REALM_DEFINE=()
if [ "${NO_CORS_PROXY:-0}" != "1" ]; then
  CERT="$RUN_DIR/proxy-cert.pem"
  KEY="$RUN_DIR/proxy-key.pem"
  if [ ! -f "$CERT" ] || [ ! -f "$KEY" ]; then
    echo "==> Generating self-signed cert for the dev proxy"
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$KEY" -out "$CERT" \
      -days 30 -subj "/CN=localhost" \
      -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" >/dev/null 2>&1
  fi

  # Trust exactly THIS cert rather than disabling certificate checking wholesale.
  SPKI=$(openssl x509 -in "$CERT" -pubkey -noout \
    | openssl pkey -pubin -outform der \
    | openssl dgst -sha256 -binary | openssl enc -base64)

  if lsof -iTCP:"$PROXY_PORT" -sTCP:LISTEN -P -n >/dev/null 2>&1; then
    echo "    CORS proxy already listening on $PROXY_PORT"
  else
    echo "==> Starting CORS/TLS dev proxy on $PROXY_PORT"
    nohup node "$ROOT/tool/cors_dev_proxy.js" "$PROXY_PORT" \
      >"$RUN_DIR/cors-proxy.log" 2>&1 &
    disown $! 2>/dev/null || true
  fi

  CHROME_TLS_FLAGS=(
    --web-browser-flag="--ignore-certificate-errors-spki-list=$SPKI"
  )
  REALM_DEFINE=(--dart-define=REALM_TOKEN_BASE="https://localhost:$PROXY_PORT")
else
  echo "    CORS proxy DISABLED - the web client cannot join a room"
fi

CHROME_MEDIA_FLAGS=()
if [ "${REAL_CAMERA:-0}" != "1" ]; then
  # --use-fake-ui: auto-grant, so the guest profile never shows a permission
  # prompt that a script cannot click. --use-fake-device: the synthetic source.
  CHROME_MEDIA_FLAGS=(
    --web-browser-flag="--use-fake-ui-for-media-stream"
    --web-browser-flag="--use-fake-device-for-media-stream"
  )
  echo "    Chrome guest: SYNTHETIC camera (REAL_CAMERA=1 to override)"
else
  echo "    Chrome guest: real camera - will contend with the macOS client"
fi

nohup flutter run -d chrome --web-browser-flag="--user-data-dir=$CHROME_PROFILE" \
  "${CHROME_MEDIA_FLAGS[@]}" "${CHROME_TLS_FLAGS[@]}" "${REALM_DEFINE[@]}" \
  >"$CHROME_LOG" 2>&1 &
CHROME_PID=$!
disown "$CHROME_PID" 2>/dev/null || true

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

# Re-check AFTER the wait loop. The loop's own probe proves the server came
# up; it cannot prove the server is still up by the time a human reads the URL.
# A liveness check that runs before the thing can die is not a liveness check.
sleep 3
if ! curl -s --max-time 3 "$APP_URL/" 2>/dev/null | grep -qi "<title>Tech World"; then
  echo "    Web app came up on $APP_URL and then DIED - see $CHROME_LOG" >&2
  echo "    (a bare '&' inside a script that exits will do this)" >&2
  exit 1
fi

command -v pbcopy >/dev/null && printf '%s' "$APP_URL" | pbcopy
cat <<MSG

    Web app: $APP_URL  (copied to clipboard)
    Chrome log: $CHROME_LOG

Next, by hand:
  1. Chrome  -> "continue as guest" (camera + mic auto-granted, synthetic)
  2. macOS   -> create/enter a room; note its name
  3. Chrome  -> join that same room from the list
  4. macOS   -> make sure YOUR camera is on: the merge needs two video
                bubbles, and one of them is your own local-player bubble
  5. Walk the avatars into OVERLAP (merge threshold is 96.0 centre-to-centre)

Take a watermark BEFORE you start playing:
  wc -l < ~/Documents/tech_world_logs/events.log

Read the results with:  tool/verify_av.sh <watermark>
Proxy log (token hops):  $RUN_DIR/cors-proxy.log
MSG

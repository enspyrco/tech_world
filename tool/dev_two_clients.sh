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

# ── Autopilot ────────────────────────────────────────────────────────────────
# Both clients drive themselves: guest sign-in, room entry, and (for the web
# guest) a walking route. The macOS client holds position, because the merge
# cases need one participant stationary while the other crosses the threshold,
# and because events.log -- the evidence -- is written by the native file sink.
#
# Set NO_AUTOPILOT=1 to drive by hand instead.
# Not `${AUTOPILOT_ROOM:-Wizard's Tower}`: bash re-parses the default operand of
# `:-` as a word even inside double quotes, so the apostrophe opens a quote that
# swallows the next 180 lines and reports the error somewhere else entirely.
AUTOPILOT_ROOM="${AUTOPILOT_ROOM:-}"
[ -n "$AUTOPILOT_ROOM" ] || AUTOPILOT_ROOM="The Wizard's Tower"
# The guest paces ACROSS the macOS client's station, so the pair crosses the
# 96px merge threshold in both directions on every cycle. Two connected clients
# that never come near each other prove connectivity and nothing else: the first
# autopiloted run left them 17 cells apart for its whole life.
AUTOPILOT_ROUTE="${AUTOPILOT_ROUTE:-21,20>27,20}"
# Two adjacent cells rather than one: a single-waypoint route is not a walk and
# does not start, so this is how the macOS client takes up a KNOWN position
# instead of wherever the map happened to spawn it.
AUTOPILOT_MACOS_ROUTE="${AUTOPILOT_MACOS_ROUTE:-24,20>24,21}"
AUTOPILOT_DWELL="${AUTOPILOT_DWELL:-2500}"
MACOS_DEFINES=()
GUEST_AUTOPILOT=()
if [ "${NO_AUTOPILOT:-0}" != "1" ]; then
  MACOS_DEFINES=(--dart-define=AUTOPILOT="room=$AUTOPILOT_ROOM;route=$AUTOPILOT_MACOS_ROUTE;dwell=$AUTOPILOT_DWELL")
  GUEST_AUTOPILOT=(--dart-define=AUTOPILOT="room=$AUTOPILOT_ROOM;route=$AUTOPILOT_ROUTE;dwell=$AUTOPILOT_DWELL")
  echo "==> Autopilot: room \"$AUTOPILOT_ROOM\" every ${AUTOPILOT_DWELL}ms"
  echo "    macOS station $AUTOPILOT_MACOS_ROUTE, guest paces $AUTOPILOT_ROUTE across it"
  echo "    (NO_AUTOPILOT=1 to drive by hand)"
fi

# Taken here, before a client can join: the old instruction told the reader to
# take it "before you start playing", which stopped being possible the moment
# the clients started playing by themselves.
WATERMARK=$(wc -l < "$HOME/Documents/tech_world_logs/events.log" 2>/dev/null || echo 0)
WATERMARK=$(echo "$WATERMARK" | tr -d ' ')

echo "==> Building + launching macOS client"
flutter build macos --debug "${MACOS_DEFINES[@]}" >"$RUN_DIR/macos-build.log" 2>&1
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
# ── Local realm-token-server + TLS in front of it ────────────────────────────
# The production mint at realm-token.imagineering.cc REFUSES browser origins by
# design, not by omission: src/cors.js rejects CORS_ALLOW_LOCALHOST=true at boot
# when NODE_ENV=production, and the Dockerfile sets it. The opt-in is "fine on a
# laptop, a hole on a public mint" in the server's own words. So the dev loop
# runs its OWN copy of the real server rather than routing around the deployed
# one by stripping the Origin header.
#
# scripts/dev.sh in that repo generates an ephemeral ES256 keypair per run and
# defaults CORS_ALLOW_LOCALHOST=true, so any Flutter dev port is accepted.
# Set NO_LOCAL_TOKEN_SERVER=1 to skip (the web client then cannot join a room).
TLS_PORT="${TLS_TERMINATOR_PORT:-8787}"
RTS_PORT="${RTS_PORT:-8790}"
RTS_DIR="${REALM_TOKEN_SERVER_DIR:-$HOME/git/orgs/enspyrco/realm-token-server}"
SECRETS="${REALM_SECRETS_FILE:-$HOME/git/orgs/enspyrco/infra/realm-token-server/secrets.yaml}"
CHROME_TLS_FLAGS=()
REALM_DEFINE=()

if [ "${NO_LOCAL_TOKEN_SERVER:-0}" != "1" ]; then
  if [ ! -x "$RTS_DIR/scripts/dev.sh" ]; then
    echo "    realm-token-server not found at $RTS_DIR" >&2
    echo "    clone enspyrco/realm-token-server, or set REALM_TOKEN_SERVER_DIR" >&2
    exit 1
  fi

  CERT="$RUN_DIR/proxy-cert.pem"
  KEY="$RUN_DIR/proxy-key.pem"
  if [ ! -f "$CERT" ] || [ ! -f "$KEY" ]; then
    echo "==> Generating self-signed cert for the TLS terminator"
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$KEY" -out "$CERT" \
      -days 30 -subj "/CN=localhost" \
      -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" >/dev/null 2>&1
  fi

  # Trust exactly THIS cert rather than disabling certificate checking wholesale.
  SPKI=$(openssl x509 -in "$CERT" -pubkey -noout \
    | openssl pkey -pubin -outform der \
    | openssl dgst -sha256 -binary | openssl enc -base64)

  # The REAL LiveKit key/secret, because the token this server mints is verified
  # by the real SFU at livekit.imagineering.cc. Everything else a local run needs
  # is ephemeral. Without these the exchange still succeeds and the room join
  # fails one hop later -- a confusing place to land, so say so up front.
  # dotenv output rather than parsing yaml inline: the extraction is two greps
  # instead of a nested interpreter, and nothing about the secret values has to
  # survive a round trip through shell quoting.
  LK_ENV=""
  if [ -f "$SECRETS" ] && command -v sops >/dev/null 2>&1; then
    LK_ENV=$(sops -d --output-type dotenv "$SECRETS" 2>/dev/null \
      | grep -E '^LIVEKIT_API_(KEY|SECRET)=' || true)
  fi

  if [ -n "$LK_ENV" ]; then
    # set -a makes each assignment an export without rewriting the lines.
    set -a
    eval "$LK_ENV"
    set +a
    echo "    LiveKit credentials: real (from $SECRETS)"
  else
    echo "    LiveKit credentials: DEV PLACEHOLDERS -- /exchange will work and" >&2
    echo "    the room join will be rejected by the SFU. Install sops and keep" >&2
    echo "    $SECRETS readable to fix." >&2
  fi

  # Always restart, never reuse. A process already listening on this port was
  # started with SOME environment, and nothing it serves reveals which LiveKit
  # key it mints with -- the credential only shows up as the JWT issuer, inside
  # a token that needs a real sign-in to obtain. Reusing it once cost a full
  # two-client run: the mint held `devkey`, every hop went green (/exchange 200,
  # /livekit-token 200, CORS correct), and the SFU refused the token one hop
  # later with "invalid API key: devkey". Port-is-occupied is a cheap proxy for
  # "the mint is configured right", and it is not one. The port is ours.
  # `|| true` is load-bearing under `set -o pipefail`: lsof exits non-zero when
  # it finds nothing, which is the NORMAL case here, and the pipeline inherits
  # that failure even though `head` succeeded. Without it the script dies on a
  # free port -- the one condition this block exists to handle.
  RTS_PID=$(lsof -tiTCP:"$RTS_PORT" -sTCP:LISTEN 2>/dev/null | head -1 || true)
  if [ -n "$RTS_PID" ]; then
    echo "    Replacing realm-token-server on $RTS_PORT (pid $RTS_PID)"
    kill "$RTS_PID" 2>/dev/null || true
    for _ in $(seq 1 10); do
      lsof -tiTCP:"$RTS_PORT" -sTCP:LISTEN >/dev/null 2>&1 || break
      sleep 1
    done
  fi
  echo "==> Starting local realm-token-server on $RTS_PORT"
  (cd "$RTS_DIR" && PORT="$RTS_PORT" nohup ./scripts/dev.sh \
    >"$RUN_DIR/realm-token-server.log" 2>&1 &)

  # Wait for the mint itself, not for the terminator in front of it: a 502 from
  # the terminator and a mint that has not finished booting look identical to
  # the Flutter client, and only one of them is worth waiting out.
  for _ in $(seq 1 30); do
    curl -s --max-time 1 "http://127.0.0.1:$RTS_PORT/healthz" 2>/dev/null \
      | grep -q '"ok":true' && break
    sleep 1
  done
  if ! curl -s --max-time 2 "http://127.0.0.1:$RTS_PORT/healthz" 2>/dev/null \
       | grep -q '"ok":true'; then
    echo "    realm-token-server never became healthy - see $RUN_DIR/realm-token-server.log" >&2
    exit 1
  fi

  # Same reasoning as the mint above: the terminator caches its upstream URL at
  # start, so a survivor from an earlier run can be pointed somewhere else.
  # `|| true` is load-bearing under `set -o pipefail`: lsof exits non-zero when
  # it finds nothing, which is the NORMAL case here, and the pipeline inherits
  # that failure even though `head` succeeded. Without it the script dies on a
  # free port -- the one condition this block exists to handle.
  TLS_PID=$(lsof -tiTCP:"$TLS_PORT" -sTCP:LISTEN 2>/dev/null | head -1 || true)
  if [ -n "$TLS_PID" ]; then
    echo "    Replacing TLS terminator on $TLS_PORT (pid $TLS_PID)"
    kill "$TLS_PID" 2>/dev/null || true
    for _ in $(seq 1 10); do
      lsof -tiTCP:"$TLS_PORT" -sTCP:LISTEN >/dev/null 2>&1 || break
      sleep 1
    done
  fi
  echo "==> Starting TLS terminator on $TLS_PORT"
  REALM_UPSTREAM="http://127.0.0.1:$RTS_PORT" PROXY_CERT_DIR="$RUN_DIR" \
    nohup node "$ROOT/tool/dev_tls_terminator.js" "$TLS_PORT" \
    >"$RUN_DIR/tls-terminator.log" 2>&1 &
  disown $! 2>/dev/null || true

  CHROME_TLS_FLAGS=(
    --web-browser-flag="--ignore-certificate-errors-spki-list=$SPKI"
  )
  REALM_DEFINE=(--dart-define=REALM_TOKEN_BASE="https://localhost:$TLS_PORT")
else
  echo "    Local token server DISABLED - the web client cannot join a room"
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
  "${GUEST_AUTOPILOT[@]}" \
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

Both clients drive themselves from here (NO_AUTOPILOT=1 to opt out):
  macOS  -> guest sign-in, enters "$AUTOPILOT_ROOM", takes station at $AUTOPILOT_MACOS_ROUTE, camera on
  Chrome -> guest sign-in, same room, paces $AUTOPILOT_ROUTE across that station

Give them ~30s to sign in, join and start publishing before reading the log.

Read the results with:  tool/verify_av.sh $WATERMARK
Token server log:        $RUN_DIR/realm-token-server.log
  TLS terminator log:      $RUN_DIR/tls-terminator.log
MSG

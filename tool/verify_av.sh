#!/usr/bin/env bash
# Read the live-session evidence for the BubbleManager seven-way split.
#
# COVERAGE, stated up front because a verifier that hides its blind spots is
# worse than none:
#   Concern 1 (AvSnapshotReporter)  - log-verifiable, macOS file sink.
#   Concern 2 (merge/render shader) - log-verifiable as of BubblesMerged /
#                                     BubblesUnmerged. Those are emitted at the
#                                     BOTTOM of the merged-surface build, after
#                                     the shader-null early return, so an event
#                                     means the surface was actually built --
#                                     not merely that two bubbles were close.
#   Concern 3 (Dreamfinder onReady) - log-verifiable, CHROME ONLY. On native the
#                                     bridge is a no-op stub, so a macOS run is
#                                     silent whether it works or not.
#
# Usage: tool/verify_av.sh [watermark-line-number]
#        The watermark is a line count in events.log taken BEFORE the session;
#        without it, historical lines are indistinguishable from tonight's.
set -uo pipefail

LOG_DIR="$HOME/Documents/tech_world_logs"
EVENTS="$LOG_DIR/events.log"
ERRORS="$LOG_DIR/errors.jsonl"
CHROME_LOG="${TMPDIR:-/tmp}/tech-world-two-clients/chrome.log"
MARK="${1:-0}"

[ -f "$EVENTS" ] || { echo "No events.log at $EVENTS - has the macOS client ever run?" >&2; exit 1; }

echo "=============================================================="
echo " Live verification readout"
echo " events.log: $(wc -l < "$EVENTS") lines (watermark: $MARK)"
echo "=============================================================="

echo
echo "--- Instrument liveness (positive control) ---"
# Silence means nothing unless we know the writer is alive.
LAST_TS=$(grep -ao '"timestamp":"[^"]*"' "$EVENTS" | tail -1 | cut -d'"' -f4)
echo "last event written: ${LAST_TS:-NONE}"
echo "file mtime:         $(date -r "$EVENTS" '+%Y-%m-%dT%H:%M:%S')"

SLICE=$(tail -n "+$((MARK + 1))" "$EVENTS")

echo
echo "--- CONCERN 1: AvSnapshotReporter ---"
SNAPS=$(printf '%s\n' "$SLICE" | grep -ac 'av_pipeline_snapshot' || true)
echo "snapshots emitted: $SNAPS"
if [ "$SNAPS" -eq 0 ]; then
  echo "VERDICT: UNVERIFIED - reporter produced nothing since the watermark."
else
  echo "capture methods seen:"
  printf '%s\n' "$SLICE" | grep -a 'av_pipeline_snapshot' \
    | jq -r 'select(.captureMethod != null) | "  \(.participant)  method=\(.captureMethod)  frames=\(.framesCaptured)  dropped=\(.framesDropped)"' \
    2>/dev/null | sort -u | tail -10
  MAXF=$(printf '%s\n' "$SLICE" | grep -a 'av_pipeline_snapshot' \
    | jq -r '.framesCaptured // 0' 2>/dev/null | sort -n | tail -1)
  echo "peak framesCaptured: ${MAXF:-0}"
  if [ "${MAXF:-0}" -gt 0 ]; then
    echo "VERDICT: VERIFIED - reporter live and frames are flowing."
  else
    echo "VERDICT: PARTIAL - reporter live but zero frames. Could be warm-up;"
    echo "         re-run after ~15s before diagnosing a capture fault."
  fi
fi

echo
echo "--- Participants in the session (is there a SECOND human?) ---"
printf '%s\n' "$SLICE" | jq -r '.participant // .playerId // empty' 2>/dev/null \
  | grep -av '^_local_player_$' | sort | uniq -c | sort -rn | head -10
HUMANS=$(printf '%s\n' "$SLICE" | jq -r '.participant // empty' 2>/dev/null \
  | grep -avE '^(bot-|agent-|_local_player_)' | sort -u | wc -l | tr -d ' ')
echo "distinct non-bot participants: $HUMANS"
[ "$HUMANS" -lt 2 ] && echo "NOTE: fewer than 2 humans - the merge group cannot reach size 2."

echo
echo "--- CONCERN 2: merge / render shader ---"
if grep -aq 'Shader failed to load' "$EVENTS"; then
  echo "VERDICT: FAILED - a shader did not load:"
  grep -a 'Shader failed to load' "$EVENTS" | tail -3
else
  MERGED=$(printf '%s\n' "$SLICE" | grep -ac '"type":"bubbles_merged"' || true)
  UNMERGED=$(printf '%s\n' "$SLICE" | grep -ac '"type":"bubbles_unmerged"' || true)
  echo "bubbles_merged: $MERGED    bubbles_unmerged: $UNMERGED"
  if [ "$MERGED" -gt 0 ]; then
    printf '%s\n' "$SLICE" | grep -a '"type":"bubbles_merged"' \
      | jq -r '"  merged \(.count): \(.participantIds|join(\" + \"))  \(.timestamp)"' \
      2>/dev/null | tail -5
    echo "VERDICT: VERIFIED - the merged surface was built with real sources."
    # Frame-rate spam would mean the transition guard regressed.
    if [ "$MERGED" -gt 50 ]; then
      echo "WARNING: $MERGED merge events is far above a plausible number of"
      echo "         real transitions - suspect the transition guard in"
      echo "         BubbleMergeRenderer.mergeTransitions has regressed."
    fi
  else
    echo "VERDICT: UNVERIFIED - no merge ever formed."
    echo "         Either the bubbles were never overlapped (< 96.0 centre-to-"
    echo "         centre), or there were fewer than two video bubbles present."
  fi
fi

echo
echo "--- CONCERN 3: Dreamfinder avatar bridge onReady (Chrome only) ---"
if [ ! -f "$CHROME_LOG" ]; then
  echo "VERDICT: UNVERIFIED - no Chrome log at $CHROME_LOG"
  echo "         Run tool/dev_two_clients.sh; a macOS-only run is silent here"
  echo "         whether the bridge works or not (native export is a stub)."
elif grep -aq 'Dreamfinder avatar bridge ready' "$CHROME_LOG"; then
  echo "VERDICT: VERIFIED - onReady fired:"
  grep -a 'Dreamfinder avatar bridge ready' "$CHROME_LOG" | tail -2
else
  echo "success line absent. Failure lines present:"
  grep -aE 'did not signal ready|Cannot find canvas|Failed to create CanvasCapture|Cannot access iframe canvas|bridge failed to initialize' \
    "$CHROME_LOG" | tail -5 || echo "  (none - bridge may simply not have been reached)"
  echo "VERDICT: UNVERIFIED"
fi

echo
echo "--- Errors since the watermark ---"
if [ -f "$ERRORS" ]; then
  tail -40 "$ERRORS" | jq -r '"\(.timestamp)  \(.type)  \(.message // "")"' 2>/dev/null | tail -8
fi
echo
echo "=============================================================="

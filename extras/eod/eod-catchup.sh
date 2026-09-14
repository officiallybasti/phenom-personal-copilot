#!/bin/bash
#
# EOD catch-up — run if last night's digest is missing.
#
# launchd: RunAtLoad (login) + StartInterval (fires after wake; the script
# no-ops in milliseconds when the digest already exists).
#
# Does not backfill more than one digest: before 20:00 local, yesterday;
# at/after 20:00, today. That is the closed-lid failure mode, not the
# July–September capture gap.

set -euo pipefail

WORKSPACE="${EOD_WORKSPACE:?Set EOD_WORKSPACE to your Cursor workspace root}"
VAULT="${EOD_VAULT:-$WORKSPACE/phenom-personal-copilot}"
AGENT_SH="${EOD_AGENT_SH:-$VAULT/extras/eod/eod-agent.sh}"
LOG_DIR="${EOD_LOG_DIR:-$HOME/Library/Logs/eod-agent}"
CATCHUP_LOG="$LOG_DIR/catchup.log"
COOLDOWN_SECS="${EOD_CATCHUP_COOLDOWN:-5400}"

mkdir -p "$LOG_DIR"

hour=$(date +%H)
hour=$((10#$hour))
if [[ "$hour" -ge 20 ]]; then
  TARGET=$(date +%Y-%m-%d)
else
  TARGET=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d yesterday +%Y-%m-%d)
fi

DIGEST="$VAULT/00_Inbox/Daily/${TARGET}-eod.md"
ATTEMPT="$LOG_DIR/catchup-attempt-${TARGET}"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$CATCHUP_LOG"; }

digest_ok() {
  [[ -f "$DIGEST" ]] && grep -q 'EOD-MEETINGS:' "$DIGEST"
}

if digest_ok; then
  exit 0
fi

now=$(date +%s)
if [[ -f "$ATTEMPT" ]]; then
  last=$(stat -f %m "$ATTEMPT" 2>/dev/null || stat -c %Y "$ATTEMPT")
  if [[ $((now - last)) -lt "$COOLDOWN_SECS" ]]; then
    log "skip $TARGET — last attempt too recent"
    exit 0
  fi
fi

if [[ ! -x "$AGENT_SH" && ! -f "$AGENT_SH" ]]; then
  log "FAIL $TARGET — missing $AGENT_SH"
  exit 1
fi

touch "$ATTEMPT"
log "run $TARGET (catch-up)"
export EOD_DATE="$TARGET"
export EOD_CATCHUP=1
# Same log dir / workspace as the nightly job.
exec /bin/bash "$AGENT_SH"

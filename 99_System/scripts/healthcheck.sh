#!/bin/bash
# Vault health — is capture actually alive?
# Usage: ./99_System/scripts/healthcheck.sh [--quiet]
# Exit:  0 healthy, 1 warning, 2 stale

set -uo pipefail

VAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$VAULT" || exit 2

QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1

TODAY=$(date +%s)
STATUS=0

say() { [[ $QUIET -eq 0 ]] && echo "$@"; return 0; }

newest_age_days() {
  local newest
  newest=$(ls -1t $1 2>/dev/null | head -1)
  [[ -z "$newest" ]] && echo -1 && return
  local mtime
  if [[ "$(basename "$newest")" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
    mtime=$(date -j -f "%Y-%m-%d" "${BASH_REMATCH[1]}" +%s 2>/dev/null \
         || date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null)
  fi
  [[ -z "${mtime:-}" ]] && mtime=$(stat -f %m "$newest" 2>/dev/null || stat -c %Y "$newest")
  echo $(( (TODAY - mtime) / 86400 ))
}

check() {
  local label="$1" age="$2" warn="$3" stale="$4"
  if   [[ "$age" -lt 0 ]];      then say "  WARN    $label — nothing yet (expected on a fresh vault)"; [[ $STATUS -lt 1 ]] && STATUS=1
  elif [[ "$age" -ge "$stale" ]]; then say "  STALE   $label — ${age}d old";        STATUS=2
  elif [[ "$age" -ge "$warn" ]];  then say "  WARN    $label — ${age}d old";        [[ $STATUS -lt 1 ]] && STATUS=1
  else say "  OK      $label — ${age}d old"
  fi
}

say "Vault health — $(date '+%Y-%m-%d %H:%M')"
say ""
say "Capture:"
check "Morning brief"   "$(newest_age_days '00_Inbox/Daily/*-brief.md')" 3 7
check "Meeting notes"   "$(newest_age_days '00_Inbox/Meetings/*.md')"    3 7
EOD_AGE=$(newest_age_days '00_Inbox/Daily/*-eod.md')
if [[ "$EOD_AGE" -lt 0 ]]; then
  say "  OK      EOD digest — optional; not enabled (see extras/eod/)"
else
  check "EOD digest" "$EOD_AGE" 3 7
fi

SOURCES_JSON="99_System/meetings/sources.json"
if command -v python3 >/dev/null 2>&1 && [[ -r "$SOURCES_JSON" ]]; then
  SRC=$(python3 - "$SOURCES_JSON" <<'PY' 2>/dev/null || true
import json, sys
cfg = json.load(open(sys.argv[1]))
name = cfg.get("active_source", "?")
src = cfg.get("sources", {}).get(name, {})
print("%s\t%d" % (name, len(src.get("unconfirmed", []))))
PY
)
  CAPTURE_NAME=${SRC%%$'\t'*}
  CAPTURE_UNCONFIRMED=${SRC##*$'\t'}
  if [[ -z "$SRC" ]]; then
    say "  STALE   Capture source — sources.json will not parse"; STATUS=2
  elif [[ "$CAPTURE_UNCONFIRMED" -gt 0 ]]; then
    say "  WARN    Capture source — $CAPTURE_NAME, $CAPTURE_UNCONFIRMED unverified value(s)"
    [[ $STATUS -lt 1 ]] && STATUS=1
  else
    say "  OK      Capture source — $CAPTURE_NAME"
  fi
else
  say "  WARN    Capture source — cannot verify"
  [[ $STATUS -lt 1 ]] && STATUS=1
fi

say ""
say "Task hygiene:"
OPEN=$(grep -c '^- \[ \]' 01_Tasks/Tasks.md 2>/dev/null || true)
DONE=$(grep -c '^- \[x\]' 01_Tasks/Tasks.md 2>/dev/null || true)
say "  $OPEN open · $DONE done"
if [[ "$OPEN" -gt 60 ]]; then
  say "  STALE   backlog past the point of trust — run plan my week"; STATUS=2
elif [[ "$DONE" -eq 0 && "$OPEN" -gt 0 ]]; then
  say "  WARN    nothing closed yet"
  [[ $STATUS -lt 1 ]] && STATUS=1
fi

say ""
say "Context layer:"
for f in 99_System/context/*.md; do
  [[ "$(basename "$f")" == "README.md" ]] && continue
  blanks=$(grep -c '\*\*Fill in' "$f" 2>/dev/null || true)
  if [[ "${blanks:-0}" -gt 0 ]]; then
    say "  WARN    $(basename "$f") — still has Fill in stubs"
    [[ $STATUS -lt 1 ]] && STATUS=1
  fi
done

say ""
case $STATUS in
  0) say "Healthy." ;;
  1) say "Degraded — see warnings above. Fine on day one." ;;
  2) say "STALE — fix capture before trusting a brief." ;;
esac

exit $STATUS

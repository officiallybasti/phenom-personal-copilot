#!/bin/bash
#
# End-of-Day Digest Agent — nightly runner
# Scheduled via launchd at 8pm daily
#
# Every run ends with exactly one "=== Completed with exit code N ===" line,
# and a failing run additionally writes the EOD-DIGEST-FAILED marker that
# 99_System/scripts/healthcheck.sh greps for. Before 2026-09 neither line was
# reachable on failure — set -e aborted the script at the claude pipeline —
# so two months of failed runs produced logs indistinguishable from quiet days.
#
# Every run also ends with one EOD-DIGEST-RESULT line carrying the capture
# source, whether that source is verified, and how many meetings the digest
# actually retrieved. Exiting 0 is not evidence of a working run: a wrong MCP
# server name produces a claude process that starts, finds no meeting tool,
# and writes a confident, empty digest. The count is what distinguishes that
# from a genuinely quiet day, and it is a number rather than prose so the
# health check can act on it without anyone reading this log.
#

set -euo pipefail

WORKSPACE="${EOD_WORKSPACE:?Set EOD_WORKSPACE to your Cursor workspace root}"
VAULT="${EOD_VAULT:-$WORKSPACE/phenom-personal-copilot}"
CLAUDE="${EOD_CLAUDE_BIN:-$HOME/.local/bin/claude}"
AGENT="eod-digest"
LOG_DIR="${EOD_LOG_DIR:-$HOME/Library/Logs/eod-agent}"
# EOD_DATE lets the login catch-up write yesterday's digest after a missed 20:00 run.
DATE="${EOD_DATE:-$(date +%Y-%m-%d)}"
DAY_NAME=$(date -j -f "%Y-%m-%d" "$DATE" '+%A, %B %d, %Y' 2>/dev/null \
  || date -d "$DATE" '+%A, %B %d, %Y')
LOG_FILE="$LOG_DIR/${DATE}.log"

SOURCES_JSON="${EOD_SOURCES_JSON:-$VAULT/99_System/meetings/sources.json}"
DIGEST_FILE="${EOD_DIGEST_FILE:-$VAULT/00_Inbox/Daily/${DATE}-eod.md}"
LOCKDIR="${EOD_LOCKDIR:-$LOG_DIR/eod-agent.lock}"
USER_AGENT_DIR="${EOD_USER_AGENT_DIR:-$HOME/.claude/agents}"
SLACK_USER_ID="${EOD_SLACK_USER_ID:?Set EOD_SLACK_USER_ID to your Slack user id}"

FAIL_MARKER="EOD-DIGEST-FAILED"
RESULT_MARKER="EOD-DIGEST-RESULT"

if ! mkdir -p "$LOG_DIR"; then
  echo "eod-agent: cannot create log directory $LOG_DIR" >&2
  exit 1
fi

if ! mkdir "$LOCKDIR" 2>/dev/null; then
  echo "eod-agent: already running (lock $LOCKDIR)" >> "$LOG_FILE" 2>/dev/null || true
  echo "eod-agent: already running (lock $LOCKDIR)" >&2
  exit 0
fi
trap 'rmdir "$LOCKDIR" 2>/dev/null || true' EXIT

echo "=== EOD Digest Agent — $DATE $(date +%H:%M:%S) catch-up=${EOD_CATCHUP:-0} ===" >> "$LOG_FILE"

# Opt-in failure notification. EOD_NOTIFY_CMD is run by bash -c with the
# message as $1, so it can be an osascript call, a curl to a Slack webhook,
# anything. Credentials belong in the launchd plist or the shell env, never here.
notify() {
  [[ -n "${EOD_NOTIFY_CMD:-}" ]] || return 0
  bash -c "$EOD_NOTIFY_CMD" eod-notify "$1" >> "$LOG_FILE" 2>&1 \
    || echo "notify hook itself failed" >> "$LOG_FILE"
}

# Populated by resolve_capture and verify_digest below. The defaults describe a
# run that died before it learned anything, which is what finish() reports if
# it is called from one of the early preconditions.
CAPTURE_SOURCE="${EOD_CAPTURE_SOURCE:-glean}"
CAPTURE_VERIFIED="unknown"
CAPTURE_TOOLS=""
MEETING_COUNT="none"
SLACK_ALERT_SENT=0

# FYI Slack when the runner itself fails (agent missing, Glean unauthenticated).
# Separate from the digest DM — this one must work even if --agent eod-digest does not.
send_failure_slack() {
  local reason="$1"
  [[ "${EOD_SKIP_FAILURE_SLACK:-0}" == "1" ]] && return 0
  [[ "$SLACK_ALERT_SENT" == "1" ]] && return 0
  SLACK_ALERT_SENT=1
  command -v "$CLAUDE" >/dev/null 2>&1 || return 0
  local fail_tools="${EOD_SLACK_TOOLS:-mcp__plugin-slack-slack__slack_send_message,mcp__claude_ai_Slack__slack_send_message,mcp__project-0-Product Co-Pilots-slack__slack_send_message}"
  local fail_prompt
  fail_prompt=$(cat <<EOF
Send one Slack DM. channel_id=${SLACK_USER_ID}. Tool: slack_send_message.
Do nothing else. Message:

*EOD Digest — ${DATE} FAILED*
${reason}

This is FYI — no reply needed. Logs: ${LOG_FILE}
If Glean needs login: \`claude mcp login glean_default\`
EOF
)
  EOD_SKIP_FAILURE_SLACK=1 "$CLAUDE" -p \
    --no-session-persistence \
    --allowedTools "$fail_tools" \
    "$fail_prompt" >> "$LOG_FILE" 2>&1 || true
}

finish() {
  local code="$1"
  if [[ "$code" -ne 0 ]]; then
    echo "$FAIL_MARKER exit=$code — ${2:-claude run failed}" >> "$LOG_FILE"
    notify "EOD digest failed ($DATE, exit $code): ${2:-claude run failed}"
    send_failure_slack "${2:-claude run failed}"
  fi
  echo "$RESULT_MARKER date=$DATE source=$CAPTURE_SOURCE verified=$CAPTURE_VERIFIED meetings=$MEETING_COUNT exit=$code" >> "$LOG_FILE"
  echo "=== Completed with exit code $code at $(date +%H:%M:%S) ===" >> "$LOG_FILE"
  exit "$code"
}

if [[ ! -x "$CLAUDE" ]]; then
  finish 1 "claude binary not found or not executable: $CLAUDE"
fi

if [[ ! -d "$WORKSPACE" ]]; then
  finish 1 "workspace directory does not exist: $WORKSPACE"
fi

# launchd does not always load project .claude/agents. Keep a user copy in sync.
mkdir -p "$USER_AGENT_DIR"
if [[ -f "$WORKSPACE/.claude/agents/${AGENT}.md" ]]; then
  cp "$WORKSPACE/.claude/agents/${AGENT}.md" "$USER_AGENT_DIR/${AGENT}.md"
  echo "agent: copied workspace definition → $USER_AGENT_DIR/${AGENT}.md" >> "$LOG_FILE"
elif [[ -f "$VAULT/.claude/agents/${AGENT}.md" ]]; then
  cp "$VAULT/.claude/agents/${AGENT}.md" "$USER_AGENT_DIR/${AGENT}.md"
  echo "agent: copied vault definition → $USER_AGENT_DIR/${AGENT}.md" >> "$LOG_FILE"
fi
if [[ ! -f "$USER_AGENT_DIR/${AGENT}.md" ]]; then
  finish 1 "agent definition ${AGENT}.md missing — expected $WORKSPACE/.claude/agents/${AGENT}.md"
fi

glean_mcp=$("$CLAUDE" mcp get glean_default 2>&1) || true
echo "glean mcp get: $glean_mcp" >> "$LOG_FILE"
if printf '%s' "$glean_mcp" | grep -qiE 'Needs authentication|not found|Unknown MCP'; then
  finish 1 "Glean MCP (glean_default) is not authenticated in Claude Code. Run: claude mcp login glean_default"
fi

cd "$WORKSPACE" || finish 1 "cannot cd into workspace: $WORKSPACE"

# Capture-source tools, as Claude Code namespaces MCP: mcp__<server>__<tool>.
#
# The adapters live in 99_System/meetings/sources.json so that the nightly run
# and the interactive rules cannot disagree about which server is current.
# Read them from there when possible; the table below is a fallback for a
# machine with no python3 or a missing vault, and is treated as unverified
# because a fallback cannot know whether it is still right.
CAPTURE_TOOLS_GLEAN="mcp__glean_default__search,mcp__glean_default__read_document,mcp__glean_default__chat"
CAPTURE_TOOLS_GRANOLA="mcp__claude_ai_Granola__list_meetings,mcp__claude_ai_Granola__get_meetings,mcp__claude_ai_Granola__get_meeting_transcript,mcp__claude_ai_Granola__query_granola_meetings"

# Emits "source<TAB>verified<TAB>comma-separated-tools" for the active adapter,
# or nothing. `verified` is no when the adapter's own `unconfirmed` array still
# lists the server name or the tool prefix — the vault's confidence marker is
# the authority on this, not a substring match on a vendor name.
read_sources_json() {
  command -v python3 >/dev/null 2>&1 || return 1
  [[ -r "$SOURCES_JSON" ]] || return 1
  python3 - "$SOURCES_JSON" <<'PY' 2>/dev/null
import json, sys
cfg = json.load(open(sys.argv[1]))
name = cfg.get("active_source")
src = cfg.get("sources", {}).get(name)
if not src:
    sys.exit(1)
prefix = src.get("claude_code_tool_prefix")
tools = [v for k, v in src.get("tools", {}).items() if not k.startswith("_")]
if not prefix or not tools:
    sys.exit(1)
unconfirmed = set(src.get("unconfirmed", []))
suspect = {"mcp_server.claude_code", "claude_code_tool_prefix"}
verified = "no" if unconfirmed & suspect else "yes"
print("\t".join([name, verified, ",".join(prefix + t for t in tools)]))
PY
}

if [[ -n "${EOD_CAPTURE_TOOLS:-}" ]]; then
  # An operator who names the tools explicitly has, by that act, verified them.
  # This is also the supported way to run before sources.json is filled in.
  CAPTURE_TOOLS="$EOD_CAPTURE_TOOLS"
  CAPTURE_VERIFIED="yes"
  echo "capture: tools set explicitly via EOD_CAPTURE_TOOLS" >> "$LOG_FILE"
elif RESOLVED=$(read_sources_json); then
  IFS=$'\t' read -r CAPTURE_SOURCE CAPTURE_VERIFIED CAPTURE_TOOLS <<< "$RESOLVED"
  echo "capture: resolved '$CAPTURE_SOURCE' from $SOURCES_JSON (verified=$CAPTURE_VERIFIED)" >> "$LOG_FILE"
else
  case "$CAPTURE_SOURCE" in
    glean)   CAPTURE_TOOLS="$CAPTURE_TOOLS_GLEAN"   ;;
    granola) CAPTURE_TOOLS="$CAPTURE_TOOLS_GRANOLA" ;;
    *)       CAPTURE_TOOLS="" ;;
  esac
  CAPTURE_VERIFIED="no"
  echo "capture: could not read $SOURCES_JSON, falling back to the built-in table" >> "$LOG_FILE"
fi

if [[ -z "$CAPTURE_TOOLS" ]]; then
  finish 1 "no capture tools for source '$CAPTURE_SOURCE'; set EOD_CAPTURE_TOOLS or fix $SOURCES_JSON"
fi

# An unverified server name does not fail the claude run — claude starts, finds
# no meeting tool, and writes a confident empty digest. Running anyway would
# produce exactly the artefact this script exists to prevent, so refuse. A
# missing digest with a failure marker is a far better outcome than a plausible
# one nobody can trust.
if [[ "$CAPTURE_VERIFIED" != "yes" ]]; then
  finish 1 "capture source '$CAPTURE_SOURCE' is unverified — confirm the Claude Code MCP server name, move it out of the adapter's \`unconfirmed\` list in $SOURCES_JSON, or set EOD_CAPTURE_TOOLS explicitly"
fi

# Slack is distribution, not capture — names are not in sources.json.
# Override with EOD_SLACK_TOOLS if Claude Code uses a different MCP prefix.
SLACK_TOOLS="${EOD_SLACK_TOOLS:-mcp__plugin-slack-slack__slack_send_message,mcp__plugin-slack-slack__slack_search_users,mcp__plugin-slack-slack__slack_read_thread,mcp__claude_ai_Slack__slack_send_message,mcp__claude_ai_Slack__slack_search_users,mcp__project-0-Product Co-Pilots-slack__slack_send_message,mcp__project-0-Product Co-Pilots-slack__slack_search_users}"
ALLOWED_TOOLS="${CAPTURE_TOOLS},${SLACK_TOOLS},Read,Write,Edit,Glob,Bash(mkdir*),Bash(mv*)"
echo "allowed tools: $ALLOWED_TOOLS" >> "$LOG_FILE"

# The count has to come from the agent, whose definition lives outside this
# repo — but the prompt does not, so the requirement is enforceable from here.
# An agent that ignores it yields meetings=unknown rather than a false zero.
CATCHUP_LINE="This is the scheduled 20:00 run."
if [[ "${EOD_CATCHUP:-0}" == "1" ]]; then
  CATCHUP_LINE="This is a catch-up run (lid was closed at 20:00 or the nightly job missed). Mark the Slack DM as (catch-up). Digest date is still ${DATE}."
fi

read -r -d '' PROMPT <<EOP || true
Run the end-of-day digest for ${DATE}. Digest weekday: ${DAY_NAME}.
${CATCHUP_LINE}

Capture source is Glean (glean_default search + read_document). Do not call
Granola. Follow .claude/agents/eod-digest.md: sync meetings, write a
high-level digest, private Slack DM to $SLACK_USER_ID. Do not append
Tasks.md. Do not write 99_System/context/. Do not ask for a reply.
Archive old inbox meetings and old eod files.

Before you finish, end the digest file with exactly this line, on its own:

<!-- EOD-MEETINGS: N -->

N is the number of meetings you retrieved from Glean for this digest date.
Write 0 if you retrieved none. The health check reads this line to tell a
quiet day apart from a broken capture connection, so do not omit it, do not
reformat it, and do not estimate — if a tool call failed, the count is 0
and you should say so in the digest body as well.
EOP

set +e
echo "$PROMPT" \
  | "$CLAUDE" -p \
    --agent "$AGENT" \
    --no-session-persistence \
    --allowedTools "$ALLOWED_TOOLS" \
  >> "$LOG_FILE" 2>&1
EXIT_CODE=${PIPESTATUS[1]}
set -e

if [[ "$EXIT_CODE" -ne 0 ]]; then
  finish "$EXIT_CODE" "claude --agent $AGENT exited $EXIT_CODE"
fi

# claude exited 0. That is not the same as having done the job.
if [[ ! -f "$DIGEST_FILE" ]]; then
  finish 1 "claude exited 0 but wrote no digest at $DIGEST_FILE"
fi

COUNT=$(sed -n 's/.*EOD-MEETINGS:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$DIGEST_FILE" | tail -1)
if [[ -n "$COUNT" ]]; then
  MEETING_COUNT="$COUNT"
else
  MEETING_COUNT="unknown"
  echo "WARN: digest has no EOD-MEETINGS marker — the agent definition is ignoring the prompt, so a broken capture source cannot be told from a quiet day" >> "$LOG_FILE"
fi

finish 0

#!/usr/bin/env bash
#
# delegation-guard.sh — make the delegation trigger structural instead of
# remembered.
#
# CLAUDE.md tells the planner to scout before opening more than ~3 files. An
# audit of 21 sessions found that instruction was followed in 4 of 15 — not
# because it was disputed, but because it is a turn-0 instruction evaluated
# 100 turns later, at the exact moment momentum is cheapest. Multi-turn
# instruction adherence decays with turn count; a hook does not.
#
# So this runs outside the model, on three events:
#
#   count   (PostToolUse)      tallies *exploration* reads, nudges at 3 and 5.
#                              Exit 2 puts the nudge in front of the planner;
#                              the tool already ran, so nothing is lost.
#   gate    (PreToolUse)       denies the 7th exploration read, naming the
#                              command to run instead. The deny reason is fed
#                              back, so the turn continues.
#   context (UserPromptSubmit) resets the per-turn budget and re-states the
#                              routing rule at turn N rather than turn 0.
#
# The counter lives in a file, not in the planner's head, because counting is
# precisely the thing it failed at.
#
# Exploration is not close reading. A file you are about to edit, a re-read, a
# short file, anything outside the repo: none of it counts. Over-firing would
# make this noise, and noise gets disabled.
#
# Escape hatches, in order of preference:
#   1. run a scout — that is the point, and it resets the budget
#   2. touch .claude/.delegation-guard-off   (disables until removed)
#   3. DELEGATION_GUARD=off in the environment
#
# Tunables: DELEGATION_NUDGE_AT (3), DELEGATION_WARN_AT (5), DELEGATION_BLOCK_AT (6)
#
set -uo pipefail

MODE=${1:-count}

# Fail open, always. A guard that breaks the session is worse than no guard:
# every unexpected path below ends in exit 0.
trap 'exit 0' ERR

NUDGE_AT=${DELEGATION_NUDGE_AT:-3}
WARN_AT=${DELEGATION_WARN_AT:-5}
BLOCK_AT=${DELEGATION_BLOCK_AT:-6}
SMALL_FILE_LINES=${DELEGATION_SMALL_FILE:-50}

INPUT=$(cat)
[[ -n $INPUT ]] || exit 0

j() { jq -r "$1 // empty" <<<"$INPUT" 2>/dev/null; }

SESSION=$(j '.session_id'); SESSION=${SESSION:-nosession}
CWD=$(j '.cwd')
PROJ=${CLAUDE_PROJECT_DIR:-${CWD:-$PWD}}
TOOL=$(j '.tool_name')

[[ ${DELEGATION_GUARD:-on} == off ]] && exit 0
[[ -e $PROJ/.claude/.delegation-guard-off ]] && exit 0

STATE="${TMPDIR:-/tmp}/claude-delegation/${SESSION//[^a-zA-Z0-9._-]/_}"
mkdir -p "$STATE" 2>/dev/null || exit 0
EXPLORED="$STATE/explored"
EDITED="$STATE/edited"
touch "$EXPLORED" "$EDITED" 2>/dev/null || exit 0

count() { wc -l <"$EXPLORED" 2>/dev/null | tr -d ' '; }

# The key identifies one act of exploration. Reads key on the path; searches
# key on the pattern too, so re-running the same grep is free but a new
# question is not.
explore_key() {
  local p
  case $TOOL in
    Read|NotebookRead) p=$(j '.tool_input.file_path'); [[ -n $p ]] && printf 'read:%s' "$p" ;;
    Grep)  p=$(j '.tool_input.path'); printf 'grep:%s:%s' "$(j '.tool_input.pattern')" "${p:-.}" ;;
    Glob)  p=$(j '.tool_input.path'); printf 'glob:%s:%s' "$(j '.tool_input.pattern')" "${p:-.}" ;;
  esac
}

# Everything here is a reason NOT to count a read. Each one is a real case
# where delegating would be wrong or pointless.
is_exempt() {
  local key=$1 path=$2

  # Already counted: re-reading a file is not new exploration.
  grep -qxF "$key" "$EXPLORED" 2>/dev/null && return 0

  if [[ -n $path ]]; then
    # A file this session already edited or wrote: that is close reading of
    # something we are changing, which must never be delegated.
    grep -qxF "$path" "$EDITED" 2>/dev/null && return 0
    # Outside the repo: scratchpads, transcripts, /var/lib/pi-tasks output.
    [[ $path == "$PROJ"/* ]] || return 0
    # Short files are cheaper to read than to describe in a brief.
    if [[ -f $path ]]; then
      local n; n=$(wc -l <"$path" 2>/dev/null || echo 0)
      (( n < SMALL_FILE_LINES )) && return 0
    fi
  fi
  return 1
}

case $MODE in

  # ── PostToolUse ───────────────────────────────────────────────────────
  count)
    case $TOOL in
      Edit|Write|NotebookEdit|MultiEdit)
        p=$(j '.tool_input.file_path')
        [[ -n $p ]] && ! grep -qxF "$p" "$EDITED" 2>/dev/null && echo "$p" >>"$EDITED"
        exit 0 ;;
      Task|Agent)
        # Delegating to a subagent is delegation. Budget resets.
        : >"$EXPLORED"; exit 0 ;;
      Bash)
        cmd=$(j '.tool_input.command')
        if grep -qE 'scripts/(scout|delegate)\.sh' <<<"$cmd"; then
          : >"$EXPLORED"
        fi
        exit 0 ;;
      Read|NotebookRead|Grep|Glob) ;;
      *) exit 0 ;;
    esac

    key=$(explore_key); [[ -n $key ]] || exit 0
    path=$(j '.tool_input.file_path')
    is_exempt "$key" "$path" && exit 0
    echo "$key" >>"$EXPLORED"
    n=$(count)

    if (( n == NUDGE_AT )); then
      { echo "[delegation] $n exploration reads this turn. If you are surveying rather than"
        echo "reading a file you're about to change, the next question goes to a scout:"
        echo "    ./scripts/scout.sh \"<your question>\""
        echo "It returns a cited report, keeps the file contents out of this context, and"
        echo "resets this counter. Blocking starts at $BLOCK_AT."
      } >&2
      exit 2
    elif (( n == WARN_AT )); then
      { echo "[delegation] $n exploration reads. One more and Read/Grep/Glob is blocked"
        echo "until a scout runs: ./scripts/scout.sh \"<your question>\""
      } >&2
      exit 2
    fi
    exit 0 ;;

  # ── PreToolUse ────────────────────────────────────────────────────────
  gate)
    case $TOOL in Read|NotebookRead|Grep|Glob) ;; *) exit 0 ;; esac
    n=$(count); (( n >= BLOCK_AT )) || exit 0

    key=$(explore_key); path=$(j '.tool_input.file_path')
    is_exempt "$key" "$path" && exit 0   # close reading is never blocked

    jq -n --arg n "$n" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: (
          "Blocked: \($n) exploration reads this turn without delegating.\n" +
          "Hand the survey to a scout instead of opening another file:\n" +
          "    ./scripts/scout.sh \"<your question>\"\n" +
          "It answers from a snapshot with file:line citations, costs ~0.3c, and keeps\n" +
          "the file contents out of this context — which is where ~60% of the token bill\n" +
          "actually goes. The counter resets once it runs.\n" +
          "Genuinely need to read this file? Re-reading an already-open file, or a file\n" +
          "you have edited this turn, is never blocked; otherwise\n" +
          "    touch .claude/.delegation-guard-off\n" +
          "disables this guard for the session."
        )
      }
    }'
    exit 0 ;;

  # ── UserPromptSubmit ──────────────────────────────────────────────────
  context)
    prev=$(count)
    : >"$EXPLORED"          # each user turn is a fresh investigation
    (( prev > 0 )) || exit 0
    jq -n --arg p "$prev" '{
      hookSpecificOutput: {
        hookEventName: "UserPromptSubmit",
        additionalContext: (
          "[delegation] Previous turn used \($p) exploration reads. Budget reset. " +
          "Surveying the repo goes to ./scripts/scout.sh; close reading of files you " +
          "are about to change stays here."
        )
      }
    }'
    exit 0 ;;

  *) exit 0 ;;
esac

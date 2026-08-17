#!/usr/bin/env bash
#
# scout.sh — ask the cheap worker model a question about this repo, get back a
# short cited report.
#
# The companion to delegate.sh. delegate.sh is for *changing* things: it clones,
# lets the worker edit, then re-runs an acceptance command and hands back a
# diff. This script is for *understanding* things, and it exists because
# exploration is what actually runs up the planner's token bill — reading ten
# files to find the one that matters costs far more than writing the fix.
#
# Four things this script does that matter:
#
#   1. The question is the argument. No brief file, no slug to invent, no task
#      directory to clean up afterwards.
#
#   2. Only the report reaches the planner. The worker's transcript — every
#      read, every grep, every file it dumped — goes to a log on disk, never to
#      stdout. If the transcript reached the planner's context we would have
#      paid the exploration cost twice and saved nothing.
#
#   3. It snapshots the working tree, not a git clone, so the scout sees your
#      uncommitted edits. The snapshot has no .git (the worker never touches
#      your git config or hooks) and is not writable by the worker, so
#      "read-only" is a filesystem property rather than a promise in a prompt.
#
#   4. It enforces an output contract: ANSWER / EVIDENCE / GAPS, with file:line
#      citations. A scout that returns prose leaves you opening the files
#      anyway; one that returns line numbers lets you open two instead of ten.
#
# Usage:
#   scripts/scout.sh "where is piworker defined and what groups does it get?"
#   scripts/scout.sh --files 'configuration.nix,flake.nix' "what pins nixos-wsl?"
#   scripts/scout.sh --full "why does the delegate script use a bundle?"
#   echo "long question..." | scripts/scout.sh -
#
# Options:
#   --files a,b   starting points to hand the scout (it may still read others)
#   --label slug  name the run directory, for when you want to find it later
#   --model M     default openrouter/z-ai/glm-5.2
#   --timeout N   seconds before the scout is killed (default 300)
#   --full        print the scout's whole reasoning trace, not just the report
#
set -euo pipefail

TASKS_ROOT=/var/lib/pi-tasks
SCOUT_ROOT="$TASKS_ROOT/.scout"
WORKER_USER=piworker
WORKER_HOME=/var/lib/piworker
REPO_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYSTEM_MD="$REPO_SRC/scripts/scout-system.md"

MODEL="openrouter/z-ai/glm-5.2"
TIMEOUT=300
FILES=""
LABEL=""
FULL=0
QUESTION=""

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
note() { printf '\033[36m==>\033[0m %s\n' "$*" >&2; }

usage() {
  sed -n '2,46p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --files)   FILES=${2:?--files needs a value}; shift 2 ;;
    --label)   LABEL=${2:?--label needs a value}; shift 2 ;;
    --model)   MODEL=${2:?--model needs a value}; shift 2 ;;
    --timeout) TIMEOUT=${2:?--timeout needs a value}; shift 2 ;;
    --full)    FULL=1; shift ;;
    -h|--help) usage 0 ;;
    -)         QUESTION="$QUESTION $(cat)"; shift ;;
    -*)        die "unknown option: $1" ;;
    *)         QUESTION="$QUESTION $1"; shift ;;
  esac
done

QUESTION="${QUESTION# }"
[[ -n ${QUESTION//[[:space:]]/} ]] \
  || die 'no question given. Try: scripts/scout.sh "where is X defined?"   (see --help)'
[[ $TIMEOUT =~ ^[0-9]+$ ]] || die "--timeout must be a whole number of seconds"
[[ -z $LABEL || $LABEL =~ ^[a-zA-Z0-9._-]+$ ]] || die "--label must be [a-zA-Z0-9._-]+ (it becomes a directory name)"

# ── Preflight ────────────────────────────────────────────────────────────
# Same checks as delegate.sh, minus everything about writing: a scout needs no
# sudo at all beyond `sudo -u piworker` to run pi.

id -u "$WORKER_USER" &>/dev/null \
  || die "user '$WORKER_USER' does not exist — is configuration.nix applied? Try: sudo nixos-rebuild switch --flake $REPO_SRC#vibeos"

id -nG | tr ' ' '\n' | grep -qx pitasks \
  || die "you are not in the 'pitasks' group *in this shell*, so you cannot create the scout's snapshot.
       Group membership only applies to new login sessions.
       Fix: run 'newgrp pitasks' or restart your WSL shell, then re-run this."

sudo -n -u "$WORKER_USER" test -r "$WORKER_HOME/.openrouter-key" \
  || die "worker cannot read $WORKER_HOME/.openrouter-key (expected mode 600, owner $WORKER_USER)"

[[ -f $SYSTEM_MD ]] || die "missing guardrails file: $SYSTEM_MD"

# ── Run directory ────────────────────────────────────────────────────────
# One per run, so several scouts can run in parallel without colliding, and so
# a question can be re-asked without first removing anything. Runs older than a
# day are swept up here rather than by you.

mkdir -p "$SCOUT_ROOT"
chmod 2750 "$SCOUT_ROOT" 2>/dev/null || true
find "$SCOUT_ROOT" -mindepth 1 -maxdepth 1 -type d -mmin +1440 -exec rm -rf {} + 2>/dev/null || true

RUNDIR="$SCOUT_ROOT/$(date +%Y%m%d-%H%M%S)-${LABEL:-$$}"
[[ -e $RUNDIR ]] && RUNDIR="$RUNDIR.$RANDOM"
mkdir "$RUNDIR"
chmod 2750 "$RUNDIR"   # worker can read and traverse, not write

# ── Snapshot the working tree ────────────────────────────────────────────
# Tracked + untracked-but-not-ignored files, which means the scout sees work
# you have not committed yet. Deleted-but-still-tracked paths are filtered out,
# or rsync would fail on them.
#
# No .git is copied. The scout loses `git log`, and in exchange the worker never
# reads your git config or hooks, and the snapshot is a plain-directory flake --
# so the "nix only sees git-tracked files" trap cannot bite it either.

mkdir "$RUNDIR/repo"
git -C "$REPO_SRC" ls-files -co --exclude-standard -z \
  | while IFS= read -r -d '' f; do [[ -e $REPO_SRC/$f ]] && printf '%s\0' "$f"; done \
  | rsync -a --from0 --files-from=- "$REPO_SRC/" "$RUNDIR/repo/"

# `rsync -a` preserves the *source* group, and as a non-root user that stamps
# your primary group ("users") onto every copied path -- overriding the setgid
# pitasks inheritance. Directories then read as aliammar:users, which piworker
# is not in, so it can traverse nothing below the top level and silently reports
# on whatever it could reach. Set the group back explicitly.
chgrp -R pitasks "$RUNDIR/repo"

# Strip write permission from everything, then give the directories back to us
# only -- a directory needs its write bit to have entries removed, so without
# this second step you could not clean the snapshot up. The worker ends with
# r-x on directories and r-- on files: it can read everything, and cannot edit,
# create, or delete anything. Nobody outside the pitasks group gets in at all.
chmod -R a-w "$RUNDIR/repo"
find "$RUNDIR/repo" -type d -exec chmod u+wx,g+rx,g-w,o-rwx {} +
find "$RUNDIR/repo" ! -type d -exec chmod g+r,o-rwx {} +

# ── Prompt ───────────────────────────────────────────────────────────────

{
  echo "# Scout question"
  echo
  echo "$QUESTION"
  echo
  if [[ -n $FILES ]]; then
    echo "## Starting points"
    echo
    # shellcheck disable=SC2016  # the backticks are literal markdown, not expansion
    tr ',' '\n' <<<"$FILES" | sed 's/^/- `/; s/$/`/'
    echo
    echo "Start there. You may read anything else in the snapshot you need."
    echo
  fi
  echo "Answer from the files in this snapshot, and report using the"
  echo "ANSWER / EVIDENCE / GAPS contract from your system prompt."
} >"$RUNDIR/QUESTION.md"

# ── Run the scout ────────────────────────────────────────────────────────
# stdout is JSON events into the transcript, never onto our stdout. `timeout` is
# the real backstop on a scout that will not stop reading; the prompt is only
# guidance.

note "scouting (model $MODEL, timeout ${TIMEOUT}s)"

PI_ARGS=(-p "$(cat "$RUNDIR/QUESTION.md")"
         --model "$MODEL"
         --no-session
         --mode json
         --no-context-files
         --tools 'read,grep,find,ls,bash'
         --append-system-prompt "$(cat "$SYSTEM_MD")")

START=$SECONDS
set +e
# shellcheck disable=SC2016  # the bash -c body expands in the *worker's* shell, not ours
timeout "${TIMEOUT}s" sudo -u "$WORKER_USER" env -i \
  HOME="$WORKER_HOME" \
  PATH=/run/current-system/sw/bin \
  TERM=dumb \
  TMPDIR=/tmp \
  RUNDIR="$RUNDIR" \
  bash -c '
    cd "$RUNDIR/repo" || exit 1
    export OPENROUTER_API_KEY="$(tr -d "[:space:]" < "$HOME/.openrouter-key")"
    exec pi "$@"
  ' _ "${PI_ARGS[@]}" </dev/null >"$RUNDIR/transcript.jsonl" 2>"$RUNDIR/stderr.log"
RC=$?
set -e
ELAPSED=$(( SECONDS - START ))

# ── Report ───────────────────────────────────────────────────────────────
# The final assistant message is the report; --full widens that to every
# assistant message, i.e. the reasoning between tool calls. Either way the tool
# calls themselves stay in the transcript, which is the whole point.
#
# There can be several `agent_end` events, not one: pi emits a fresh
# agent_start/agent_end pair for every auto-retry, and a retry that dies on a
# provider error contributes an empty one. So take the last agent_end that
# actually carries text, rather than the last one that exists.

if (( FULL )); then
  JQ_PICK='.[]'
else
  JQ_PICK='last'
fi

REPORT=$(jq -rs "
  [ .[]
    | select(.type == \"agent_end\")
    | [ (.messages // [])[] | select(.role == \"assistant\") ]
    | select(length > 0)
    | [ $JQ_PICK ]
    | [ .[] | (.content // [])[] | select(.type == \"text\") | .text ]
    | join(\"\n\")
    | select(length > 0)
  ] | last // \"\"
" "$RUNDIR/transcript.jsonl" 2>/dev/null | sed '/^$/N;/^\n$/D') || REPORT=""

if [[ -z ${REPORT//[[:space:]]/} ]]; then
  # A silent empty report is the failure mode that costs a whole round trip, so
  # say what went wrong instead of printing nothing.
  if (( RC == 124 )); then
    printf '\033[31mSCOUT TIMED OUT\033[0m after %ss — no report produced.\n' "$TIMEOUT" >&2
    printf 'Narrow the question or raise --timeout.\n' >&2
  else
    printf '\033[31mSCOUT PRODUCED NO REPORT\033[0m (exit %s).\n' "$RC" >&2
  fi
  # Provider failures (rate limits especially) are reported inside the JSON
  # stream, not on stderr -- so without this you get "no report" and no reason,
  # and the reason is usually "retry in a minute".
  ERR=$(jq -rs '[.[] | select(.type | startswith("auto_retry"))
                     | (.finalError // .errorMessage // empty)] | last // empty' \
        "$RUNDIR/transcript.jsonl" 2>/dev/null || true)
  if [[ -n ${ERR//[[:space:]]/} ]]; then
    printf '\nProvider error (after auto-retries):\n' >&2
    head -3 <<<"$ERR" | cut -c1-300 >&2
  elif jq -es 'any(.[]; .type == "message_end" and .message.stopReason == "error")' \
         "$RUNDIR/transcript.jsonl" >/dev/null 2>&1; then
    # A model your key cannot reach fails exactly like this: one empty assistant
    # message, stopReason "error", and no error text anywhere in the stream.
    printf '\nThe model returned an error with no message — usually a model your\n' >&2
    printf 'key cannot reach. Try a different --model (%s was requested).\n' "$MODEL" >&2
  fi
  if [[ -s $RUNDIR/stderr.log ]]; then
    printf '\nLast lines of stderr:\n' >&2
    tail -20 "$RUNDIR/stderr.log" | cut -c1-300 >&2
  fi
  printf '\nTranscript: %s\n' "$RUNDIR/transcript.jsonl" >&2
  exit 2
fi

COST=$(jq -rs '[.[] | select(.type == "message_end") | .message.usage.cost.total // 0] | add // 0' \
       "$RUNDIR/transcript.jsonl" 2>/dev/null || echo 0)

printf '\n%s\n' "$REPORT"
printf '\n\033[2m(%s, %ss, transcript: %s)\033[0m\n' \
  "$(awk -v c="$COST" 'BEGIN { printf (c < 0.01 ? "%.2fc" : "$%.3f"), (c < 0.01 ? c * 100 : c) }')" \
  "$ELAPSED" "$RUNDIR/transcript.jsonl"

if (( RC == 124 )); then
  printf '\033[33mwarning:\033[0m scout was killed at the %ss timeout — the report above may be incomplete.\n' "$TIMEOUT" >&2
fi

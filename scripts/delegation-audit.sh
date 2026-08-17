#!/usr/bin/env bash
#
# delegation-audit.sh — measure whether the planner actually delegates.
#
# Run this monthly. Without it there is no feedback signal at all: the first
# audit (2026-08-17) found 11 of 15 tool-using sessions had invoked no worker
# whatsoever, which had gone unnoticed for the entire life of the setup.
#
# Reads Claude Code's own session transcripts and, per session, counts
# exploration (Read/Grep/Glob plus read-only bash) against worker invocations.
# Exploration always exceeds delegation — the question is by how much, and
# whether *any* session is delegating at all.
#
# Usage: scripts/delegation-audit.sh [transcript-dir]
#
set -uo pipefail

DIR=${1:-$HOME/.claude/projects/-home-aliammar-vibeos}
[[ -d $DIR ]] || { echo "no transcript directory: $DIR" >&2; exit 1; }

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

TMP=$(mktemp) && trap 'rm -f "$TMP"' EXIT

printf '%-9s %-11s %6s %5s %6s %6s %6s %6s\n' session date tools read bash scout deleg subag
printf -- '----------------------------------------------------------------\n'

t_tools=0 t_read=0 t_bash=0 t_scout=0 t_deleg=0 t_sub=0 sessions=0 delegating=0

for f in "$DIR"/*.jsonl; do
  [[ -e $f ]] || continue
  jq -r 'select(.message.content|type=="array") | .message.content[]?
         | select(.type=="tool_use")
         | [.name, ((.input.command // "")|gsub("\n";" "))] | @tsv' "$f" 2>/dev/null >"$TMP"

  tools=$(wc -l <"$TMP" | tr -d ' ')
  (( tools > 0 )) || continue
  d=$(jq -r 'select(.timestamp) | .timestamp' "$f" 2>/dev/null | head -1 | cut -c1-10)

  read_t=$(awk -F'\t' '$1=="Read"||$1=="Grep"||$1=="Glob"' "$TMP" | wc -l | tr -d ' ')
  subag=$(awk -F'\t' '$1=="Task"||$1=="Agent"' "$TMP" | wc -l | tr -d ' ')
  scout=$(grep -c 'scripts/scout\.sh' "$TMP" || true)
  deleg=$(grep 'scripts/delegate\.sh' "$TMP" | grep -vc -- '--scout' || true)
  bashi=$(awk -F'\t' '$1=="Bash"' "$TMP" | grep -Ec '(cat|head|tail|sed -n|rg|grep|find|ls|wc|awk|jq)' || true)

  printf '%-9s %-11s %6s %5s %6s %6s %6s %6s\n' \
    "$(basename "$f" | cut -c1-8)" "$d" "$tools" "$read_t" "$bashi" "$scout" "$deleg" "$subag"

  sessions=$((sessions+1))
  (( scout + deleg + subag > 0 )) && delegating=$((delegating+1))
  t_tools=$((t_tools+tools)); t_read=$((t_read+read_t)); t_bash=$((t_bash+bashi))
  t_scout=$((t_scout+scout)); t_deleg=$((t_deleg+deleg)); t_sub=$((t_sub+subag))
done

printf -- '----------------------------------------------------------------\n'
printf '%-9s %-11s %6s %5s %6s %6s %6s %6s\n' TOTAL '' "$t_tools" "$t_read" "$t_bash" "$t_scout" "$t_deleg" "$t_sub"

explore=$((t_read + t_bash))
workers=$((t_scout + t_deleg + t_sub))
echo
echo "sessions with tool calls        : $sessions"
echo "sessions that delegated at all  : $delegating"
echo "exploration ops                 : $explore"
echo "worker invocations              : $workers"
if (( workers > 0 )); then
  echo "ratio                           : $((explore / workers)) exploration ops per delegation"
else
  echo "ratio                           : no delegation at all"
fi
echo
if (( sessions > 0 )) && (( delegating * 2 < sessions )); then
  echo "VERDICT: fewer than half of sessions delegate. Check that the guard hooks in"
  echo ".claude/settings.json are still installed and firing (scripts/delegation-guard.sh)."
else
  echo "VERDICT: delegation is happening in most sessions."
fi

#!/usr/bin/env bash
#
# delegate.sh — hand a scoped task to the cheap worker model, then hand the
# result back for review.
#
# The idea: an expensive planner (Claude) writes a precise brief; a cheap model
# (GLM 5.2 via OpenRouter, driven by `pi`) does the mechanical work in an
# isolated clone as the unprivileged `piworker` account; the planner reviews
# the resulting diff. See configuration.nix for why `piworker` exists.
#
# Three things this script does that matter:
#
#   1. It runs `pi` with the task clone as the working directory. `pi` inherits
#      the caller's cwd, and piworker cannot traverse /home/aliammar (0700), so
#      invoking it from ~/vibeos hangs before it does anything at all.
#
#   2. It works on a `git clone`, never a `git worktree`. A worktree's .git is
#      a pointer into the real repo, so the worker would need write access to
#      ~/vibeos/.git — including the shared .git/hooks directory, which would
#      let it run code as you on your next git command.
#
#   3. It re-runs the acceptance command itself after the worker finishes,
#      rather than believing the worker's summary. Cheap models report success
#      they did not verify; this is the check that catches it.
#
# Usage:
#   scripts/delegate.sh --allow 'home.nix' --brief brief.md my-task
#   echo "Add package X to systemPackages" | scripts/delegate.sh --allow 'configuration.nix' add-x
#
set -euo pipefail

TASKS_ROOT=/var/lib/pi-tasks
WORKER_USER=piworker
WORKER_HOME=/var/lib/piworker
REPO_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYSTEM_MD="$REPO_SRC/scripts/worker-system.md"

MODEL="openrouter/z-ai/glm-5.2"
ACCEPT='nix build --no-link --no-write-lock-file .#nixosConfigurations.vibeos.config.system.build.toplevel'
ALLOW=""
BRIEF_FILE=""
SCOUT=0
KEEP=0

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
note() { printf '\033[36m==>\033[0m %s\n' "$*"; }

usage() {
  sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --allow)  ALLOW=${2:?--allow needs a value}; shift 2 ;;
    --brief)  BRIEF_FILE=${2:?--brief needs a value}; shift 2 ;;
    --accept) ACCEPT=${2:?--accept needs a value}; shift 2 ;;
    --model)  MODEL=${2:?--model needs a value}; shift 2 ;;
    --scout)  SCOUT=1; shift ;;
    --keep)   KEEP=1; shift ;;
    -h|--help) usage 0 ;;
    -*)       die "unknown option: $1" ;;
    *)        SLUG=$1; shift ;;
  esac
done

: "${SLUG:?usage: delegate.sh [options] <slug>   (see --help)}"
[[ $SLUG =~ ^[a-zA-Z0-9._-]+$ ]] || die "slug must be [a-zA-Z0-9._-]+ (it becomes a directory name)"

# ── Preflight ────────────────────────────────────────────────────────────
# Fail early and specifically. Every one of these has bitten during setup.

id -u "$WORKER_USER" &>/dev/null \
  || die "user '$WORKER_USER' does not exist — is configuration.nix applied? Try: sudo nixos-rebuild switch --flake $REPO_SRC#vibeos"

id -nG | tr ' ' '\n' | grep -qx pitasks \
  || die "you are not in the 'pitasks' group *in this shell*, so you won't be able to read the worker's output.
       Group membership only applies to new login sessions.
       Fix: run 'newgrp pitasks' or restart your WSL shell, then re-run this."

sudo -n -u "$WORKER_USER" test -r "$WORKER_HOME/.openrouter-key" \
  || die "worker cannot read $WORKER_HOME/.openrouter-key (expected mode 600, owner $WORKER_USER)"

[[ -f $SYSTEM_MD ]] || die "missing guardrails file: $SYSTEM_MD"

TASKDIR="$TASKS_ROOT/$SLUG"
[[ -e $TASKDIR ]] && die "$TASKDIR already exists — pick another slug, or remove it: sudo rm -rf $TASKDIR"

# Read the brief before doing any setup, so a missing brief fails cheaply.
if [[ -n $BRIEF_FILE ]]; then
  [[ -f $BRIEF_FILE ]] || die "brief file not found: $BRIEF_FILE"
  BRIEF=$(cat "$BRIEF_FILE")
else
  [[ -t 0 ]] && die "no --brief given and stdin is a terminal; pipe a brief in or pass --brief <file>"
  BRIEF=$(cat)
fi
[[ -n ${BRIEF//[[:space:]]/} ]] || die "brief is empty"

# ── Set up the isolated task directory ───────────────────────────────────
# Cloned as you (piworker can't read your home), then handed over wholesale.

note "cloning $REPO_SRC -> $TASKDIR/repo"
mkdir -p "$TASKDIR"
git clone --quiet --no-hardlinks "$REPO_SRC" "$TASKDIR/repo"
BASE=$(git -C "$TASKDIR/repo" rev-parse HEAD)
git -C "$TASKDIR/repo" checkout -q -b "task/$SLUG"

{
  echo "# Task: $SLUG"
  echo
  echo "$BRIEF"
  echo
  echo "## Files you may modify"
  echo
  if [[ -n $ALLOW ]]; then
    tr ',' '\n' <<<"$ALLOW" | sed 's/^/- `/; s/$/`/'
  else
    echo "- (unrestricted — but stay close to the task)"
  fi
  echo
  echo "## Acceptance command"
  echo
  echo 'Run this from the repository root before you finish. It must exit 0.'
  echo
  echo '```'
  echo "$ACCEPT"
  echo '```'
} >"$TASKDIR/TASK.md"

cp "$SYSTEM_MD" "$TASKDIR/SYSTEM.md"

# Ownership split, deliberately:
#   $TASKDIR       stays yours, group-writable  -> you can write the transcript
#                                                  here, the worker can drop its
#                                                  result bundle here
#   $TASKDIR/repo  goes to the worker           -> it edits and commits freely
#
# You must never run `git` *inside* $TASKDIR/repo. It is a repository the
# worker controls, and git reads configuration from the repo it operates on --
# `uploadpack.packObjectsHook` in a hostile .git/config executes commands on
# fetch. Extraction happens through a bundle (see below), which is inert data.
chmod 2770 "$TASKDIR"
sudo chown -R "$WORKER_USER:pitasks" "$TASKDIR/repo"
sudo chmod -R g+rX "$TASKDIR/repo"

# ── Run the worker ───────────────────────────────────────────────────────

PI_ARGS=(-p "$(cat "$TASKDIR/TASK.md")" --model "$MODEL" --no-session
         --append-system-prompt "$(cat "$SYSTEM_MD")")
if (( SCOUT )); then
  # Scout mode: explore and report, never edit. Cheap way to keep repo
  # exploration off the expensive model's token bill.
  PI_ARGS+=(--tools read,grep,find,ls)
  note "running worker in SCOUT mode (read-only tools)"
else
  note "running worker on task '$SLUG' with model $MODEL"
fi

set +e
sudo -u "$WORKER_USER" env -i \
  HOME="$WORKER_HOME" \
  PATH=/run/current-system/sw/bin \
  TERM=dumb \
  TASKDIR="$TASKDIR" \
  bash -c '
    cd "$TASKDIR/repo" || exit 1
    export OPENROUTER_API_KEY="$(tr -d "[:space:]" < "$HOME/.openrouter-key")"
    exec pi "$@"
  ' _ "${PI_ARGS[@]}" </dev/null 2>&1 | tee "$TASKDIR/pi-output.log"
WORKER_RC=${PIPESTATUS[0]}
set -e

note "worker exited with status $WORKER_RC (full transcript: $TASKDIR/pi-output.log)"

if (( SCOUT )); then
  note "scout run complete — no diff expected"
  exit 0
fi

# ── Review gates ─────────────────────────────────────────────────────────
# Everything below is the planner's check, not the worker's claim.
#
# All git inspection runs AS THE WORKER (`sudo -u`), for two reasons: the repo
# is worker-owned so git would otherwise refuse with "dubious ownership", and
# we do not want your uid executing anything git reads out of that repo.

# Commit whatever the worker left behind, so the result is capturable whether
# or not it thought to commit. `git add -A` also picks up new files.
sudo -u "$WORKER_USER" git -C "$TASKDIR/repo" add -A
sudo -u "$WORKER_USER" git -C "$TASKDIR/repo" \
  -c user.name='pi worker' -c user.email='piworker@localhost' \
  commit -q -m "delegated: $SLUG" >/dev/null 2>&1 || true

mapfile -t CHANGED < <(sudo -u "$WORKER_USER" git -C "$TASKDIR/repo" diff --name-only "$BASE" | sort -u)

if (( ${#CHANGED[@]} == 0 )); then
  die "worker changed nothing. Read $TASKDIR/pi-output.log to see why."
fi

printf '\n\033[1mFiles changed:\033[0m\n'
printf '  %s\n' "${CHANGED[@]}"

# Gate 1: scope. Out-of-scope edits are the classic cheap-model failure.
if [[ -n $ALLOW ]]; then
  IFS=',' read -ra PATTERNS <<<"$ALLOW"
  VIOLATIONS=()
  for f in "${CHANGED[@]}"; do
    ok=0
    for pat in "${PATTERNS[@]}"; do
      [[ -z $pat ]] && continue
      # shellcheck disable=SC2053  # glob match against the allowlist is intended
      [[ $f == $pat ]] && { ok=1; break; }
    done
    (( ok )) || VIOLATIONS+=("$f")
  done
  if (( ${#VIOLATIONS[@]} )); then
    printf '\n\033[31mSCOPE VIOLATION\033[0m — outside --allow "%s":\n' "$ALLOW"
    printf '  %s\n' "${VIOLATIONS[@]}"
  fi
fi

# Gate 2: the locks from CLAUDE.md. The worker has no sudo so it cannot
# activate anything, but it can still edit these lines in the config.
if sudo -u "$WORKER_USER" git -C "$TASKDIR/repo" diff "$BASE" \
     | grep -nE '^\+.*(wsl\.|system\.stateVersion|security\.sudo|privilegedAutomation)' ; then
  printf '\n\033[31mGUARDRAIL HIT\033[0m — diff touches a protected option above. Review carefully.\n'
fi

# Gate 3: re-run acceptance ourselves. This is the point of the whole script:
# the worker's own summary is not evidence.
printf '\n'
note "re-running acceptance command independently"
set +e
sudo -u "$WORKER_USER" env -i \
  HOME="$WORKER_HOME" PATH=/run/current-system/sw/bin TASKDIR="$TASKDIR" ACCEPT="$ACCEPT" \
  bash -c 'cd "$TASKDIR/repo" && eval "$ACCEPT"' </dev/null 2>&1 | tail -25
ACCEPT_RC=${PIPESTATUS[0]}
set -e

printf '\n'
if (( ACCEPT_RC == 0 )); then
  printf '\033[32mACCEPTANCE PASSED\033[0m (%s)\n' "$ACCEPT"
else
  printf '\033[31mACCEPTANCE FAILED\033[0m rc=%s — do not trust the worker'"'"'s summary.\n' "$ACCEPT_RC"
fi

# Export the work as a bundle. A bundle is inert data: fetching from it does
# not read the worker's .git/config, so none of that repo's hooks or
# pack-objects settings can execute in your session.
BUNDLE="$TASKDIR/result.bundle"
sudo -u "$WORKER_USER" git -C "$TASKDIR/repo" bundle create "$BUNDLE" "$BASE..task/$SLUG" 2>/dev/null \
  && note "result bundle: $BUNDLE" \
  || printf '\033[33mwarning:\033[0m could not create bundle (no new commits?)\n'

cat <<EOF

Review the diff from your own repo (safe -- bundle, not the worker's repo):

  git -C $REPO_SRC fetch $BUNDLE 'task/$SLUG:refs/delegate/$SLUG'
  git -C $REPO_SRC diff HEAD...refs/delegate/$SLUG

Take the work if you want it:

  git -C $REPO_SRC merge --ff-only refs/delegate/$SLUG
  # or, to keep your own message:  git -C $REPO_SRC cherry-pick HEAD..refs/delegate/$SLUG

EOF

(( KEEP )) || printf 'Task dir kept at %s (remove with: sudo rm -rf %s)\n' "$TASKDIR" "$TASKDIR"
exit "$ACCEPT_RC"

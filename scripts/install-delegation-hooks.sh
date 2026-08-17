#!/usr/bin/env bash
#
# install-delegation-hooks.sh — wire delegation-guard.sh into this project's
# .claude/settings.json.
#
# This exists as a script you run rather than an edit Claude makes, because
# Claude Code's own classifier blocks the assistant from writing hook config —
# a hook is code that runs on every tool call, so installing one is your
# decision, not its own. Run it yourself:
#
#     ./scripts/install-delegation-hooks.sh
#
# Idempotent: re-running replaces the three delegation hooks and leaves every
# other setting alone. `--uninstall` removes them again.
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="$REPO/.claude/settings.json"
# shellcheck disable=SC2016  # must stay literal: Claude Code expands it, not us
GUARD='"$CLAUDE_PROJECT_DIR"/scripts/delegation-guard.sh'

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
[[ -x $REPO/scripts/delegation-guard.sh ]] || { echo "missing scripts/delegation-guard.sh" >&2; exit 1; }

mkdir -p "$REPO/.claude"
[[ -f $SETTINGS ]] || echo '{}' >"$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak"

if [[ ${1:-} == --uninstall ]]; then
  jq 'del(.hooks.UserPromptSubmit, .hooks.PreToolUse, .hooks.PostToolUse)
      | if (.hooks | length) == 0 then del(.hooks) else . end' \
     "$SETTINGS.bak" >"$SETTINGS"
  echo "removed delegation hooks from $SETTINGS (backup: $SETTINGS.bak)"
  exit 0
fi

jq --arg cmd "$GUARD" '
  .hooks = ((.hooks // {}) + {
    UserPromptSubmit: [
      { hooks: [ { type: "command", command: ($cmd + " context"), timeout: 10 } ] }
    ],
    PreToolUse: [
      { matcher: "Read|NotebookRead|Grep|Glob",
        hooks: [ { type: "command", command: ($cmd + " gate"), timeout: 10 } ] }
    ],
    PostToolUse: [
      { matcher: "Read|NotebookRead|Grep|Glob|Edit|MultiEdit|Write|NotebookEdit|Bash|Task|Agent",
        hooks: [ { type: "command", command: ($cmd + " count"), timeout: 10 } ] }
    ]
  })' "$SETTINGS.bak" >"$SETTINGS"

echo "installed delegation hooks into $SETTINGS (backup: $SETTINGS.bak)"
echo
jq '.hooks | keys' "$SETTINGS"
echo
echo "Restart Claude Code (or start a new session) for hooks to take effect."
echo "Disable temporarily:  touch $REPO/.claude/.delegation-guard-off"
echo "Remove entirely:      $0 --uninstall"

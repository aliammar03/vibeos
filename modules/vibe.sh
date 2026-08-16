# Terminal landing page.
#
# Printed by zsh on login (wired up in modules/landing.nix). Run it any time
# with `vibe`. Set VIBE_NO_GREET=1 to keep it quiet at login.
#
# This is just a shell script — it frames fastfetch with a header, a greeting
# and a tip. fastfetch itself does all the actual system probing.

# Where the config repo lives; landing.nix exports this, but default sanely
# so the script still works if you run it by hand from a bare shell.
FLAKE="${VIBE_FLAKE:-$HOME/vibeos}"

# ── Catppuccin Mocha, as truecolor escapes ────────────────────────────────
# Catppuccin's nix module themes programs it knows about (bat, btop, starship
# ...) but it has no fastfetch or shell-script support, so these are copied by
# hand from the Mocha palette to match everything else.
PEACH=$'\033[38;2;250;179;135m'   # the Claude accent colour
MAUVE=$'\033[38;2;203;166;247m'
GREEN=$'\033[38;2;166;227;161m'
TEXT=$'\033[38;2;205;214;244m'
SUBTEXT=$'\033[38;2;166;173;200m'
OVERLAY=$'\033[38;2;108;112;134m'
SURFACE=$'\033[38;2;88;91;112m'
RESET=$'\033[0m'
BOLD=$'\033[1m'

# Half about the Claude workflow on this box, half plain shell tricks — and a
# couple of reminders that underneath the paint this is stock NixOS.
TIPS=(
  "ask claude for a change in plain english — it edits the config repo, never the running system directly"
  "\`nix-agent diff\` shows exactly what a rebuild would change, before it changes anything"
  "every change claude makes is a git commit — \`git revert HEAD\` undoes any one of them"
  "claude has to ask before switching generations. that rule lives in CLAUDE.md, in the config repo"
  "\`git -C ~/vibeos log --oneline\` is the complete history of this machine"
  "nothing here is magic — it's stock nixos. configuration.nix is the whole box"
  "a rebuild never destroys the old system. every generation is still there, still bootable"
  "\`sudo nixos-rebuild switch --rollback\` puts you back one generation, immediately"
  "\`nix-agent build\` catches config mistakes without touching what you're running on"
  "\`z <dir>\` jumps anywhere you've been before — zoxide learns your habits as you go"
  "ctrl-r searches your whole shell history through fzf"
  "\`ll\` is eza: filetype icons, per-file git status, human-readable sizes"
  "\`rg <pattern>\` searches every file in the tree and honours .gitignore"
  "\`fd <name>\` finds files without needing to remember find(1) syntax"
  "\`btop\` for live cpu, memory and process view. \`q\` to leave"
  "\`zellij\` splits this terminal into panes that survive a disconnect"
  "\`bat <file>\` is cat with syntax highlighting and a pager"
)

# ── layout ────────────────────────────────────────────────────────────────
# The full NixOS logo is 46 columns wide; with fastfetch's padding the longest
# value lands around column 100. Below that the fetch wraps into noise, so the
# whole landing has a wide mode and a narrow mode.
WIDE_AT=100

cols=$(tput cols 2>/dev/null || echo 80)

if [ "$cols" -ge "$WIDE_AT" ]; then
  max=100
else
  max=66
fi
width=$((cols - 4))
[ "$width" -gt "$max" ] && width=$max
[ "$width" -lt 24 ] && width=24

rule() {
  local i=0 out=""
  while [ "$i" -lt "$width" ]; do
    out="$out─"
    i=$((i + 1))
  done
  printf '%s%s%s\n' "  $SURFACE" "$out" "$RESET"
}

# ── header ────────────────────────────────────────────────────────────────
# One line, not a wordmark banner. The host and user are already printed by
# fastfetch's own title row just below, so repeating them here only pads it.
echo
printf '  %s✳%s %sa claude-managed nixos%s\n' \
  "$PEACH" "$RESET" "$OVERLAY" "$RESET"
rule
echo # fastfetch leaves a row below the logo, so match it above

# ── the actual fetch ──────────────────────────────────────────────────────
# Config lives at ~/.config/fastfetch/config.jsonc, written by landing.nix.
# Narrow terminals get nixos_old_small instead: it's pure ASCII, so it can't
# break in any font, and at 13 columns it leaves room for the values.
if [ "$cols" -ge "$WIDE_AT" ]; then
  fastfetch
else
  fastfetch --logo nixos_old_small
fi

rule

# ── greeting ──────────────────────────────────────────────────────────────
# First name comes from git, so there's nothing to hardcode or keep in sync.
name=$(git config --get user.name 2>/dev/null | cut -d' ' -f1)
[ -z "$name" ] && name="$USER"
name=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')

# 10# forces base 10 — otherwise "08" and "09" are invalid octal.
hour=$((10#$(date +%H)))
if [ "$hour" -lt 5 ]; then
  hello="still up"
elif [ "$hour" -lt 12 ]; then
  hello="good morning"
elif [ "$hour" -lt 18 ]; then
  hello="good afternoon"
elif [ "$hour" -lt 22 ]; then
  hello="good evening"
else
  hello="good night"
fi

when=$(date '+%A %-d %B, %H:%M' | tr '[:upper:]' '[:lower:]')
printf '  %s✳%s %s%s, %s%s%s — %s%s\n' \
  "$PEACH" "$RESET" "$TEXT" "$hello" "$BOLD$MAUVE" "$name" "$RESET$TEXT" "$when" "$RESET"

# ── nudge, only when there's something to nudge about ─────────────────────
# On this box the config *is* the OS, so uncommitted work is worth flagging.
if [ -d "$FLAKE/.git" ]; then
  dirty=$(git -C "$FLAKE" status --porcelain 2>/dev/null | wc -l)
  if [ "$dirty" -gt 0 ]; then
    noun="changes"
    [ "$dirty" -eq 1 ] && noun="change"
    printf '  %s✳%s %sheads up%s %s·%s %s%s uncommitted %s in the config repo%s\n' \
      "$PEACH" "$RESET" "$PEACH" "$RESET" "$SURFACE" "$RESET" \
      "$SUBTEXT" "$dirty" "$noun" "$RESET"
  fi
fi

# ── tip of the login ──────────────────────────────────────────────────────
tip="${TIPS[$((RANDOM % ${#TIPS[@]}))]}"
printf '  %s✳%s %stip%s %s·%s %s%s%s\n\n' \
  "$PEACH" "$RESET" "$GREEN" "$RESET" "$SURFACE" "$RESET" \
  "$SUBTEXT" "$tip" "$RESET"

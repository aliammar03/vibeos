{ config, pkgs, ... }:
let
  # This repo. Both fastfetch and the greeter want to poke at its git state.
  flake = "${config.home.homeDirectory}/vibeos";

  # Catppuccin Mocha as raw ANSI parameters — fastfetch wraps whatever string
  # you give it in \e[...m. The catppuccin nix module has no fastfetch support,
  # so unlike bat/btop/starship these have to be copied in by hand. If you ever
  # change `catppuccin.flavor` in home.nix, these won't follow automatically.
  mocha = {
    pink = "38;2;245;194;231";
    mauve = "38;2;203;166;247";
    peach = "38;2;250;179;135";
    yellow = "38;2;249;226;175";
    green = "38;2;166;227;161";
    teal = "38;2;148;226;213";
    sky = "38;2;137;220;235";
    sapphire = "38;2;116;199;236";
    blue = "38;2;137;180;250";
    lavender = "38;2;180;190;254";
    subtext0 = "38;2;166;173;200";
    surface2 = "38;2;88;91;112";
  };

  # A horizontal rule inside the info column. A plain `separator` module would
  # be the obvious choice, but it auto-sizes to ~15 characters with no length
  # option, which looks accidental next to a 50-column info block. A `custom`
  # line gives us the exact width. Used twice: under the title, and above the
  # NixOS-specific facts at the bottom.
  infoRule = {
    type = "custom";
    format = "────────────────────────────────────────────────────";
    outputColor = mocha.surface2;
  };

  # The landing screen: header + fastfetch + greeting. Kept as a real shell
  # script (modules/vibe.sh) rather than an inline Nix string so it stays
  # readable and doesn't need every $ and quote escaped.
  vibe = pkgs.writeShellScriptBin "vibe" ''
    export PATH=${pkgs.lib.makeBinPath [
      pkgs.fastfetch
      pkgs.coreutils
      pkgs.git
      pkgs.ncurses # tput, for terminal width
    ]}:$PATH
    export VIBE_FLAKE=${flake}
    ${builtins.readFile ./vibe.sh}
  '';
in
{
  home.packages = [ vibe ];

  # fastfetch is neofetch's actively-maintained successor — same idea, but it
  # runs in ~30ms instead of ~2s (it matters when it's on every login) and it
  # takes a real structured config instead of a giant bash file.
  programs.fastfetch.enable = true;

  programs.fastfetch.settings = {
    logo = {
      type = "builtin";
      # The full "NixOS" logo, NOT "nixos_small". The small one is drawn with
      # Symbols for Legacy Computing (U+1FB38 and friends) — a Unicode block
      # almost no font actually ships, so it renders as half snowflake, half
      # tofu. The full logo uses only U+2580–259F block elements, which every
      # font that can draw a block at all supports. It costs 20 rows and 46
      # columns; see the width guard in vibe.sh for what happens when the
      # terminal is too narrow for that.
      source = "NixOS";
      color = {
        "1" = mocha.blue;
        "2" = mocha.mauve;
      };
      # top = 0 because the greeter already prints a blank line above the
      # fetch; anything more and the logo drifts away from the header rule.
      padding = {
        top = 0;
        left = 2;
        right = 3;
      };
    };

    display = {
      separator = "  ";
      key.width = 13; # pad keys so all values line up in one column
      color = {
        keys = mocha.mauve;
        title = mocha.pink;
        output = mocha.subtext0; # values, dimmer than the keys
      };
      # 3 = show the number *and* a bar, for memory/disk. Note fastfetch
      # hardcodes the bar's colours to ANSI green (filled) and bright white
      # (empty) — there's no option for it, so those two follow whatever
      # scheme the terminal emulator itself is set to, not Catppuccin here.
      percent = {
        type = 3;
        green = 50; # bar goes yellow past 50%, red past 80%
        yellow = 80;
      };
      bar = {
        char = {
          elapsed = "━";
          total = "─";
        };
        border = {
          left = "";
          right = "";
        };
        width = 12;
      };
    };

    # Keys are lowercase to match the greeter, and coloured in a running
    # gradient down the list rather than all one colour.
    modules = [
      # Two blank rows so the info column sits centred against the 20-row
      # logo instead of hanging off the top of it.
      { type = "break"; }
      { type = "break"; }

      { type = "title"; } # user@host — the only place the hostname appears
      infoRule
      {
        type = "os";
        key = "  os";
        keyColor = mocha.mauve;
      }
      {
        type = "kernel";
        key = "  kernel";
        keyColor = mocha.pink;
      }
      {
        type = "uptime";
        key = "  uptime";
        keyColor = mocha.peach;
      }
      {
        type = "packages";
        key = "  packages";
        keyColor = mocha.yellow;
      }
      {
        type = "shell";
        key = "  shell";
        keyColor = mocha.green;
      }
      {
        type = "terminal";
        key = "  terminal";
        keyColor = mocha.teal;
      }
      {
        type = "cpu";
        key = "  cpu";
        keyColor = mocha.sky;
      }
      {
        type = "memory";
        key = "  memory";
        keyColor = mocha.sapphire;
      }
      {
        type = "disk";
        key = "  disk";
        keyColor = mocha.blue;
        folders = "/";
      }
      {
        type = "localip";
        key = "  network";
        keyColor = mocha.lavender;
        showIpv6 = false;
      }

      infoRule

      # ── the part a stock neofetch can't tell you ──────────────────────
      # Which generation you're actually running, and when you switched to it.
      # `readlink` on the profile gives "system-42-link"; the symlink's own
      # mtime is when nixos-rebuild last pointed it here.
      {
        type = "command";
        key = "  generation";
        keyColor = mocha.mauve;
        text = ''printf '%s · switched %s' "$(readlink /nix/var/nix/profiles/system | cut -d- -f2)" "$(date -d @"$(stat -c %Y /nix/var/nix/profiles/system)" '+%b %-d, %H:%M')"'';
      }

      # The state of this repo, which on this box is the state of the OS.
      {
        type = "command";
        key = "  config";
        keyColor = mocha.pink;
        text = ''cd ${flake} 2>/dev/null || exit 0; d=$(git status --porcelain | wc -l); [ "$d" -eq 0 ] && s=clean || s="$d dirty"; printf '%s@%s · %s · %s commits' "$(git branch --show-current)" "$(git rev-parse --short HEAD)" "$s" "$(git rev-list --count HEAD)"'';
      }

      # Interpolated at build time, so this costs nothing at runtime and can
      # never drift from the claude-code actually installed.
      {
        type = "command";
        key = "✳ claude";
        keyColor = mocha.peach;
        text = "printf 'claude-code ${pkgs.claude-code.version}'";
      }
    ];
  };

  # `ff` for just the fetch; `vibe` (from home.packages) for the whole landing.
  programs.zsh.shellAliases.ff = "fastfetch";

  # Print the landing on login. mkOrder 1500 puts this after the general
  # config block (1000), so plugins and the prompt are set up first.
  #
  # The guards matter more than they look: without them this fires in every
  # subshell, every new zellij pane, and every shell Claude Code opens.
  programs.zsh.initContent = pkgs.lib.mkOrder 1500 ''
    if [[ -o interactive && -t 1 \
          && -z "$ZELLIJ" && -z "$TMUX" && -z "$CLAUDECODE" \
          && -z "$VIBE_NO_GREET" \
          && "$TERM" != "dumb" && ''${SHLVL:-1} -le 1 ]]; then
      vibe
    fi
  '';
}

{ pkgs, catppuccin, ... }:
{
  # WSL integration (module comes from the flake input, not a channel path)
  wsl.enable = true;
  wsl.defaultUser = "aliammar";

  # Flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Allow unfree (Claude Code is unfree)
  nixpkgs.config.allowUnfree = true;

  # Your user
  users.users.aliammar = {
    isNormalUser = true;
    # "pitasks" is a shared handoff group: it lets you read and clean up the
    # delegated worker's task clones under /var/lib/pi-tasks without sudo.
    # NOTE: adding yourself to a group only takes effect in a NEW login
    # session. After the first switch, run `newgrp pitasks` or restart your
    # WSL shell, otherwise you'll still get "permission denied" there.
    extraGroups = [ "wheel" "pitasks" ];
    shell = pkgs.zsh;
  };

  # Passwordless sudo on this single-user WSL box (delete to require a password)
  security.sudo.wheelNeedsPassword = false;

  # ── Delegated agent worker ───────────────────────────────────────────
  # Unprivileged identity that runs the GLM worker (pi-coding-agent) on
  # delegated tasks, so a cheap model can do mechanical work without having
  # your privileges.
  #
  # Why a separate user at all: pi executes bash with NO confirmation
  # prompts by design ("no permission popups" is an upstream design goal).
  # Running it as aliammar would hand an unattended model passwordless root,
  # because of security.sudo.wheelNeedsPassword above. This account is the
  # boundary that makes that safe.
  #
  # The isolation rests on three facts:
  #   1. NOT in "wheel"        -> no sudo at all.
  #   2. /home/aliammar is 0700 -> cannot read your SSH keys, gh token, or
  #                                ~/.claude config. It cannot even `cd` there.
  #   3. Its own primary group  -> `isNormalUser` would otherwise default the
  #                                group to "users" (gid 100), which is also
  #                                YOUR primary group. That would silently
  #                                share every group-readable file between
  #                                you and the worker, so we override it.
  #
  # Blast radius is therefore its own home plus /var/lib/pi-tasks.
  users.groups.piworker = { };
  users.groups.pitasks = { };

  users.users.piworker = {
    isNormalUser = true;
    description = "Delegated coding-agent worker (GLM via OpenRouter)";
    group = "piworker"; # deliberately not the default "users" -- see above
    extraGroups = [ "pitasks" ]; # write access to the task handoff dir
    createHome = true;
    home = "/var/lib/piworker";
    homeMode = "700"; # keeps the OpenRouter key unreadable to other accounts
  };

  # Handoff directory for delegated task clones. Lives OUTSIDE the worker's
  # 0700 home so you can review diffs without sudo.
  #   2770 = setgid, so files created by the worker inherit the "pitasks"
  #          group and stay readable by you; no access for anyone else.
  systemd.tmpfiles.rules = [
    "d /var/lib/pi-tasks 2770 piworker pitasks -"
  ];

  # Tools — sets you up for GitHub (Phase 2.5) and Claude (Phase 3) in one rebuild.
  # Personal/dotfile-level tools (zellij, fzf, eza, delta, btop, and their
  # shell integration) live in home.nix now — see home-manager wiring below.
  # Claude can add more here later.
  environment.systemPackages = with pkgs; [
    git
    gh
    claude-code
    ripgrep # fast recursive grep (`rg`)
    fd # fast, user-friendly `find` alternative
    # Coding-agent CLI used as the delegated worker. Binary is `pi`.
    # 26.05 ships 0.75.4 (unstable has 0.84.1) -- if we ever need a newer
    # flag, that's the reason to reach for an overlay.
    pi-coding-agent
  ];

  # zsh: system-level registration only (/etc/shells, /etc/zshrc, and
  # completion for system packages). Plugins/aliases/prompt are in home.nix.
  programs.zsh.enable = true;
  programs.zsh.enableCompletion = true;

  # home-manager: per-user dotfiles (see home.nix). useGlobalPkgs avoids a
  # second nixpkgs evaluation; backupFileExtension means activation renames
  # a conflicting pre-existing dotfile instead of refusing to switch.
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "hm-backup";
  home-manager.users.aliammar = import ./home.nix;

  # Makes `catppuccin.*` options available inside home.nix.
  home-manager.sharedModules = [ catppuccin.homeModules.catppuccin ];

  # Nerd Font — needed for the icons/glyphs in the starship prompt and eza.
  #
  # IMPORTANT WSL CAVEAT: this installs the font into *Linux*. Windows
  # Terminal draws text with fonts installed in *Windows*, so this alone
  # will NOT make the glyphs render. You also have to install the .ttf
  # files on the Windows side and pick the font in Windows Terminal.
  # Installing here anyway gives us a stable local path to copy from,
  # and covers any WSLg GUI apps later.
  fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];

  # nix-agent: MCP server exposing NixOS build/diff/switch/rollback to Claude.
  # Module comes from the nix-agent flake input (see flake.nix).
  programs.nix-agent.enable = true;

  # Pins NIX_AGENT_FLAKE on the binary so it always targets THIS repo,
  # never some other flake. Upstream calls this an anti-footgun, not a
  # security boundary — don't rely on it to contain a hostile caller.
  programs.nix-agent.flake = /home/aliammar/vibeos;

  # Narrow NOPASSWD rules for nixos-rebuild dry-activate/switch/rollback,
  # so nix-agent's privileged tools don't hang on a sudo password prompt.
  # NOTE: redundant on this box — wheelNeedsPassword = false above already
  # grants aliammar passwordless sudo for everything. Safe to delete both
  # of these lines if that global setting stays.
  programs.nix-agent.privilegedAutomation.enable = true;
  programs.nix-agent.privilegedAutomation.user = "aliammar";

  networking.hostName = "vibeos";

  # Keep exactly as generated — do not bump.
  system.stateVersion = "26.05";
}

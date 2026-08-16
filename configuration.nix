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

    # Public keys allowed to SSH in (see the SSH section below).
    # Public keys are not secrets — keeping them in git is the point, so
    # this box's access list is reviewable in the config rather than
    # hidden in a dotfile. Paste in the contents of the *.pub file from
    # the Ubuntu machine, keeping the whole single line.
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMY3q277EOHizg5Ji/WUU7WvUi4X/ezbRPebk65lQVBJ aliammar@RK-W"
    ];
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
    jq # command-line JSON processor -- avoids fragile `grep` on JSON output
    shellcheck # static analysis linter for shell scripts (lints scripts/delegate.sh)
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

  # ── SSH server (inbound) ─────────────────────────────────────────────
  # Lets you `ssh aliammar@<this box>` from another machine. The outbound
  # direction (ssh FROM here) needs no config — the client ships with NixOS.
  #
  # Three WSL-specific things, because they're the parts that bite:
  #
  #   1. The Windows-side .wslconfig sets networkingMode=mirrored, so this
  #      VM shares the Windows host's LAN address instead of sitting behind
  #      WSL's usual NAT. That means NO `netsh interface portproxy` rule is
  #      needed — port 22 here is reachable as port 22 on the host's IP.
  #      If mirrored mode is ever turned off, that changes and forwarding
  #      becomes necessary again.
  #   2. .wslconfig also sets firewall=true, so inbound packets are filtered
  #      by the *Hyper-V* firewall, which is separate from both the ordinary
  #      Windows firewall and the NixOS one below. It needs its own rule
  #      (New-NetFirewallHyperVRule) on the Windows side, once.
  #   3. sshd only runs while the distro is running. Close every WSL window
  #      and Windows eventually shuts the VM down, taking sshd with it —
  #      this is not a machine that answers SSH while nobody's logged in.
  services.openssh.enable = true;

  # Keys only, no passwords. Both of these matter: turning off
  # PasswordAuthentication alone still leaves keyboard-interactive, which is
  # a separate auth path that can also reach PAM and accept a password.
  services.openssh.settings.PasswordAuthentication = false;
  services.openssh.settings.KbdInteractiveAuthentication = false;
  services.openssh.settings.PermitRootLogin = "no";

  # Only you. Without this the delegated worker account (piworker, above)
  # would also be a valid SSH target — and that account exists specifically
  # to be an isolation boundary, so letting it be reachable over the
  # network works against the reason it exists.
  services.openssh.settings.AllowUsers = [ "aliammar" ];

  # Opens port 22 in the NixOS firewall. This is already the default; it's
  # spelled out because it's only one of the three firewalls in play here
  # (see note 2 above) and the explicit line makes that easier to remember.
  services.openssh.openFirewall = true;

  networking.hostName = "vibeos";

  # Keep exactly as generated — do not bump.
  system.stateVersion = "26.05";
}

{ pkgs, ... }:
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
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
  };

  # Passwordless sudo on this single-user WSL box (delete to require a password)
  security.sudo.wheelNeedsPassword = false;

  # Tools — sets you up for GitHub (Phase 2.5) and Claude (Phase 3) in one rebuild.
  # Claude can add more here later.
  environment.systemPackages = with pkgs; [
    git
    gh
    claude-code
    ripgrep # fast recursive grep (`rg`)
    fd # fast, user-friendly `find` alternative
    bat # `cat` with syntax highlighting
    zellij # terminal multiplexer
    fzf # fuzzy finder
    eza # modern `ls` (aliased below)
    delta # syntax-highlighting pager for `git diff`
    btop # resource monitor
  ];

  # Modern terminal environment: zsh + starship + zoxide, aliases for eza.
  programs.zsh.enable = true;
  programs.zsh.enableCompletion = true;
  programs.zsh.autosuggestions.enable = true;
  programs.zsh.syntaxHighlighting.enable = true;

  programs.starship.enable = true;

  programs.zoxide.enable = true;
  programs.zoxide.enableZshIntegration = true;

  programs.fzf.keybindings = true;
  programs.fzf.fuzzyCompletion = true;

  environment.shellAliases = {
    ls = "eza";
    ll = "eza -la";
    la = "eza -a";
    lt = "eza --tree";
  };

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

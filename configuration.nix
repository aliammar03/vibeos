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
  };

  # Passwordless sudo on this single-user WSL box (delete to require a password)
  security.sudo.wheelNeedsPassword = false;

  # Tools — sets you up for GitHub (Phase 2.5) and Claude (Phase 3) in one rebuild.
  # Claude can add more here later.
  environment.systemPackages = with pkgs; [
    git
    gh
    claude-code
  ];

  networking.hostName = "vibeos";

  # Keep exactly as generated — do not bump.
  system.stateVersion = "26.05";
}

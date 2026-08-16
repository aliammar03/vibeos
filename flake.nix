{
  description = "VibeOS - Claude-managed NixOS on WSL";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    # MCP server that lets Claude build/diff/switch this config.
    # Deliberately NOT following our nixpkgs: upstream targets nixos-unstable,
    # and pinning it to 26.05 risks breaking its Python build.
    nix-agent.url = "github:JEFF7712/nix-agent";

    # Per-user dotfile management (zsh, starship, git, etc). Pinned to the
    # release-26.05 branch so it tracks our nixpkgs; follows it explicitly
    # so we don't get a second nixpkgs copy in the closure.
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Catppuccin theming. `catppuccin.enable = true` in home.nix themes every
    # supported program at once (bat, btop, delta, eza, fzf, starship, zellij,
    # zsh-syntax-highlighting) so they all match exactly instead of us
    # hand-copying hex codes into eight different config formats.
    # release-26.05 matches our nixpkgs/home-manager pins.
    catppuccin.url = "github:catppuccin/nix/release-26.05";
    catppuccin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixos-wsl, nix-agent, home-manager, catppuccin, ... }: {
    nixosConfigurations.vibeos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      # Makes the catppuccin input visible to configuration.nix, which
      # registers its home-manager module (see home-manager.sharedModules).
      specialArgs = { inherit catppuccin; };

      modules = [
        nixos-wsl.nixosModules.default
        nix-agent.nixosModules.default
        home-manager.nixosModules.home-manager
        ./configuration.nix
      ];
    };
  };
}

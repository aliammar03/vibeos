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
  };

  outputs = { self, nixpkgs, nixos-wsl, nix-agent, ... }: {
    nixosConfigurations.vibeos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-wsl.nixosModules.default
        nix-agent.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}

{
  description = "pi-mono";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/default";
    bun2nix.url = "github:nix-community/bun2nix?ref=2.1.0";
    bun2nix.inputs.nixpkgs.follows = "nixpkgs";
    bun2nix.inputs.systems.follows = "systems";
  };

  nixConfig = {
    extra-substituters = [
      "https://pi.cachix.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "pi.cachix.org-1:lGeoGJaZ5ZDabuRzkcD5EBTNnDM4HJ1vqeOxlWk1Flk="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
      bun2nix,
    }:
    let
      current = builtins.fromJSON (builtins.readFile ./VERSION.json);
      inherit (current) rev hash;
      inherit (current.projects.coding-agent) npmDepsHash;
      version = nixpkgs.lib.removePrefix "v" rev;

      forEachSystem = nixpkgs.lib.genAttrs (import systems);
    in
    rec {
      packages = forEachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          bunPkgs = import nixpkgs {
            inherit system;
            overlays = [ bun2nix.overlays.default ];
          };

          src = pkgs.fetchFromGitHub {
            owner = "earendil-works";
            repo = "pi";
            inherit rev hash;
          };

        in
        rec {
          default = coding-agent;
          coding-agent = pkgs.callPackage ./coding-agent/package.nix {
            inherit src version npmDepsHash;
          };
          coding-agent-bun = bunPkgs.callPackage ./coding-agent/package-bun.nix {
            inherit src version;
          };
        }
      );

      lib =
        let
          coding-agent = import ./coding-agent/lib.nix {
            inherit self;
            inherit (nixpkgs) lib;
          };
        in
        {
          inherit (coding-agent) mkCodingAgent;
        };

      nixosModules = rec {
        default = coding-agent;
        coding-agent = import ./coding-agent/module.nix self;
      };

      homeModules = rec {
        default = coding-agent;
        coding-agent = import ./coding-agent/home-manager.nix self;
      };
      homeManagerModules = homeModules;

      overlays = {
        default =
          _final: prev:
          let
            inherit (prev.stdenv.hostPlatform) system;
          in
          {
            pi-coding-agent = self.packages.${system}.coding-agent;
            pi-coding-agent-bun = self.packages.${system}.coding-agent-bun;
          };
      };

      formatter = forEachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        pkgs.nixfmt
      );
    };
}

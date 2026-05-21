{
  description = "pi-mono";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/default";
  };

  nixConfig = {
    extra-substituters = [ "https://pi.cachix.org" ];
    extra-trusted-public-keys = [
      "pi.cachix.org-1:lGeoGJaZ5ZDabuRzkcD5EBTNnDM4HJ1vqeOxlWk1Flk="
    ];
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
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

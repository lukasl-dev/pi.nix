# pi.nix

A Nix flake for [pi](https://github.com/earendil-works/pi), the terminal coding agent.

It provides:

- packages for `nix run` / `nix build`
- NixOS and Home Manager modules
- an overlay exposing `pkgs.pi-coding-agent`
- `lib.mkCodingAgent` for building a configured wrapper

> [!IMPORTANT]
> This is not the official Nix flake for pi (there isn't one). See [earendil-works/pi#2310](https://github.com/earendil-works/pi/issues/2310) for context.

## Quick start

```bash
nix run github:lukasl-dev/pi.nix --accept-flake-config
```

Or build it locally:

```bash
nix build .#coding-agent --accept-flake-config
```

## Usage

```nix
{
  inputs.pi.url = "github:lukasl-dev/pi.nix";
}
```

### Binary cache

Build results are pushed to [pi.cachix.org](https://pi.cachix.org). The flake declares the substituter and public key via `nixConfig`, so consumers can use `--accept-flake-config` or configure it explicitly:

```nix
nix.settings = {
  extra-substituters = [ "https://pi.cachix.org" ];
  extra-trusted-public-keys = [
    "pi.cachix.org-1:lGeoGJaZ5ZDabuRzkcD5EBTNnDM4HJ1vqeOxlWk1Flk="
  ];
};
```

### NixOS

```nix
{ inputs, config, ... }:
{
  imports = [ inputs.pi.nixosModules.default ];

  programs.pi.coding-agent = {
    enable = true;
    # users = [ "lukas" ]; # defaults to all normal users
    # rules = ''Be concise.'';
    # skills = [ ./skills/my-skill ];
    # extensions = [ ./extensions/my-extension.ts ];
    # themes = [ ./themes/catppuccin-mocha.json ];
    # promptTemplates = [ ./prompts ];
    # models = ./models.json;
    # extraArgs = [ "--provider" "openai" "--model" "gpt-5" ];
    # environment.OPENAI_API_KEY = config.age.secrets.openai.path;
  };
}
```

### Home Manager

```nix
{ inputs, config, ... }:
{
  imports = [ inputs.pi.homeModules.default ];

  programs.pi.coding-agent = {
    enable = true;
    # rules = ''Be concise.'';
    # skills = [ ./skills/my-skill ];
    # models = ./models.json;
    # environment.OPENAI_API_KEY = config.age.secrets.openai.path;
  };
}
```

### Overlay

```nix
{ inputs, pkgs, ... }:
{
  nixpkgs.overlays = [ inputs.pi.overlays.default ];
  environment.systemPackages = [ pkgs.pi-coding-agent ];
}
```

### Custom package

```nix
{ inputs, pkgs, ... }:
let
  pi = inputs.pi.lib.mkCodingAgent {
    inherit pkgs;
    modules = [{
      pi.coding-agent = {
        rules = ''Be concise.'';
        skills = [ ./skills/my-skill ];
        extraArgs = [ "--provider" "openai" "--model" "gpt-5" ];
      };
    }];
  };
in
pi.package
```

## Options

Common options under `programs.pi.coding-agent` / `pi.coding-agent`:

- `enable`
- `package`
- `rules`
- `skills`
- `extensions`
- `themes`
- `promptTemplates`
- `models` (NixOS/Home Manager modules only)
- `users` (NixOS module only)
- `extraArgs`
- `environment`

# pi.nix

A small Nix flake for [pi](https://github.com/earendil-works/pi), the terminal coding agent. It gives you:

- `nix run`
- `nix build`
- a small NixOS module for declarative setup

## Why

The upstream `pi` repo does not ship a `flake.nix`, so this exists to make pi easy to use from Nix without going through npm/node.

See [#2310](https://github.com/earendil-works/pi/issues/2310) for context.

## Binary cache

Build results are pushed to [pi.cachix.org](http://pi.cachix.org/). The flake declares the substituter and public key via `nixConfig`, so consumers just need `--accept-flake-config`, or:

```nix
nix.settings = {
    extra-substituters = [ "https://pi.cachix.org" ];
    extra-trusted-public-keys = [
        "pi.cachix.org-1:lGeoGJaZ5ZDabuRzkcD5EBTNnDM4HJ1vqeOxlWk1Flk="
    ];
};
```

## Run

```sh
nix run github:lukasl-dev/pi.nix --accept-flake-config
```

## Build

```sh
nix build github:lukasl-dev/pi.nix --accept-flake-config
# or locally:
nix build .#coding-agent --accept-flake-config
```

## NixOS Module

```nix
# flake.nix
{
  inputs.pi.url = "github:lukasl-dev/pi.nix";
  # ...
}

# pi.nix
{ config, inputs, pkgs, ... }:
{
  imports = [
    inputs.pi.nixosModules.default
  ];

  programs.pi.coding-agent = {
    enable = true;

    # custom package
    # package = inputs.pi.packages.${pkgs.stdenv.hostPlatform.system}.coding-agent;

    # target users
    # users = [ "lukas" ]; # defaults to all normal users

    # appended to the system prompt
    # rules = ''
    #   # AGENTS.md
    #   Be concise.
    # '';

    # extra skills
    # skills = [ ./skills/my-skill ];

    # extra extensions
    # extensions = [ ./extensions/my-extension.ts ];

    # extra themes
    # themes = [ ./themes/catppuccin-mocha.json ];

    # extra prompt templates
    # promptTemplates = [ ./prompts ./prompt-templates/review.md ];

    # ~/.pi/agent/models.json
    # models = ./models.json;

    # extra raw CLI args
    # extraArgs = [ "--provider" "openai" "--model" "gpt-5" ];

    # environment variables or env file
    # environment = {
    #   OPENAI_API_KEY = config.age.secrets.openai.path;
    # };
    # environment = ./pi.env;
  };
}
```

## Overlay

```nix
# flake.nix
{
  inputs.pi.url = "github:lukasl-dev/pi.nix";
  # ...
}

# configuration.nix or a module
{ inputs, pkgs, ... }:
{
  nixpkgs.overlays = [ inputs.pi.overlays.default ];

  environment.systemPackages = [
    # aliases to inputs.pi.packages.${pkgs.stdenv.hostPlatform.system}.coding-agent
    pkgs.pi-coding-agent
  ];
}
```


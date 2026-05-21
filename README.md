# pi.nix

A Nix flake for configuring [pi](https://github.com/earendil-works/pi), the terminal coding agent. It gives you:

- `nix run`
- `nix build`
- a NixOS module for declarative setup
- a Home Manager module for declarative setup
- a generic package builder for declarative setup (like nvf/nixvim)

## Why

The upstream `pi` repo does not ship a `flake.nix`, so this exists to make pi easy to use from Nix without going through npm/node.

See [#2310](https://github.com/earendil-works/pi/issues/2310) for context.

> [!IMPORTANT]
> **This repository is not the official Nix flake of pi.**

## Build and Run

You can build/run `pi.nix` via the classical Nix way:

```bash
# build locally
nix build .#coding-agent --accept-flake-config

# run from remote
nix run github:lukasl-dev/pi.nix --accept-flake-config
```

## Usages

This flake offers different ways to use and configure pi.

### NixOS Module

```nix
# flake.nix
{
  inputs.pi.url = "github:lukasl-dev/pi.nix";
  # ...
}

# pi.nix
{ inputs, config, pkgs, ... }:
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

### NixOS Overlay

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

### Generic Package Builder

```nix
# flake.nix
{
  inputs.pi.url = "github:lukasl-dev/pi.nix";
  # ...
}

# pi.nix
{ inputs, ... }:
let
  package = inputs.pi.lib.mkCodingAgent {
    inherit pkgs;
    modules = [
      {
        pi.coding-agent = {
          # custom package
          # package = inputs.pi.packages.${pkgs.stdenv.hostPlatform.system}.coding-agent;

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

          # extra raw CLI args
          # extraArgs = [ "--provider" "openai" "--model" "gpt-5" ];

          # environment variables or env file
          # environment = {
          #   OPENAI_API_KEY = config.age.secrets.openai.path;
          # };
          # environment = ./pi.env;
        };
      }
    ];
    extraSpecialArgs = {};
  }.package;
in
...
```

### Home Manager Module

```nix
# flake.nix
{
  inputs.pi.url = "github:lukasl-dev/pi.nix";
  # ...
}

# pi.nix
{ inputs, config, pkgs, ... }:
{
  imports = [
    inputs.pi.homeModules.default
  ];

  programs.pi.coding-agent = {
    enable = true;

    # custom package
    # package = inputs.pi.packages.${pkgs.stdenv.hostPlatform.system}.coding-agent;

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

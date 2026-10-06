{
  self,
  jail-nix,
  optionPath ? [
    "pi"
    "coding-agent"
  ],
}:
{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (pkgs.stdenv.hostPlatform) system;
  inherit (self.packages.${system}) coding-agent;
  cfg = lib.attrByPath optionPath { } config;
in
{
  options = lib.setAttrByPath optionPath {
    package = lib.mkOption {
      type = lib.types.package;
      default = coding-agent;
      description = "The pi coding-agent package to install.";
    };

    wsl = lib.mkOption {
      type = lib.types.bool;
      default = false;
      internal = true;
    };

    jail = {
      enable = lib.mkEnableOption "bubblewrap isolation for pi using jail.nix";

      permissions = lib.mkOption {
        type = lib.types.functionTo (lib.types.listOf lib.types.raw);
        default =
          combinators:
          with combinators;
          [
            network
            mount-cwd
          ]
          ++ lib.optional cfg.wsl (try-readonly "/mnt/wsl/resolv.conf");
        defaultText =
          lib.literalExpression
            # nix
            ''
              combinators: with combinators; [
                network
                mount-cwd
              ] ++ lib.optional cfg.wsl (
                try-readonly "/mnt/wsl/resolv.conf"
              )
            '';
        description = ''
          Additional permissions passed to jail.nix when wrapping pi. The
          default allows model API access and mounts the runtime working
          directory read-write. On NixOS-WSL, it also exposes WSL's generated
          resolver configuration so DNS works inside the jail.

          Access to pi's agent configuration directory is always provided
          separately and does not need to be included here. The jail is
          supported only on Linux.
        '';
        example =
          lib.literalExpression # nix
            ''
              combinators: with combinators; [
                network
                mount-cwd
                (add-pkg-deps [
                  pkgs.jq
                  pkgs.gnumake
                  pkgs.python3
                ])
                (try-readonly (noescape "~/.gitconfig"))
              ]
            '';
      };
    };

    models = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a pi models.json file to install in pi's agent configuration
        directory. This defaults to {file}`~/.pi/agent/models.json` and can be
        overridden with `environment.PI_CODING_AGENT_DIR`.
      '';
      example = lib.literalExpression "./models.json";
    };

    rules = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.either lib.types.lines (lib.types.addCheck lib.types.path builtins.isPath)
      );
      default = null;
      description = ''
        Extra instructions to append to pi's system prompt via
        `--append-system-prompt`. This can be inline text or a Nix path.
      '';
      example = lib.literalExpression ''
        ./AGENTS.md
      '';
    };

    extensions = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.path lib.types.str);
      default = [ ];
      description = ''
        Extension paths to pass to pi via repeated `--extension` flags for every invocation.
      '';
    };

    skills = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Skill paths to pass to pi via repeated `--skill` flags for every invocation.
      '';
      example = lib.literalExpression ''
        [
          ./skills/my-skill
          ./skills/nixpkgs
        ]
      '';
    };

    themes = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Theme paths to pass to pi via repeated `--theme` flags for every invocation.
      '';
    };

    promptTemplates = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Prompt template paths to pass to pi via repeated `--prompt-template` flags for every invocation.
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Extra raw CLI arguments to always append when launching pi.
      '';
      example = lib.literalExpression ''
        [ "--provider" "openai" "--model" "gpt-5" ]
      '';
    };

    environment = lib.mkOption {
      type =
        let
          nixPath = lib.types.addCheck lib.types.path builtins.isPath;
          taggedValue = lib.types.attrTag {
            file = lib.mkOption {
              type = lib.types.either lib.types.str nixPath;
              description = "File whose contents are exported at runtime.";
            };
            value = lib.mkOption {
              type = lib.types.str;
              description = "Literal value to export.";
            };
          };
          environmentValue =
            (lib.types.coercedTo (lib.types.either lib.types.str nixPath) (
              legacyValue:
              throw ''
                Direct ${
                  if builtins.isString legacyValue then "string" else "Nix path"
                } environment values are ambiguous and no longer supported.

                Use an explicit tagged value instead:

                  environment.NAME.value = "literal value";
                  environment.NAME.file = config.sops.secrets.name.path;
              ''
            ) taggedValue)
            // {
              description = "attribute set containing exactly one of `file` or `value`";
            };
          attrs = lib.types.submodule {
            freeformType = lib.types.attrsOf environmentValue;

            options.PI_CODING_AGENT_DIR = lib.mkOption {
              type = lib.types.nullOr environmentValue;
              default = null;
              description = ''
                Directory pi uses for its agent configuration.
                Corresponds to the `PI_CODING_AGENT_DIR` environment variable.
              '';
              example = lib.literalExpression ''{ value = "''${config.home.homeDirectory}/.pi/agent"; }'';
            };
          };
          checkedAttrs = lib.types.addCheck attrs (
            values: lib.all lib.isValidPosixName (builtins.attrNames values)
          );
        in
        lib.types.nullOr (
          (lib.types.either lib.types.path checkedAttrs)
          // {
            inherit (attrs) getSubOptions;
            description = "shell environment file or attribute set with POSIX environment variable names";
          }
        );
      default = null;
      description = ''
        Extra environment to set before launching pi.

        This can either be a shell environment file that is sourced with `set -a`,
        or an attribute set mapping environment variable names to tagged values.
        `{ value = string; }` exports a literal value, while `{ file = path; }`
        reads and exports the file at runtime. The latter supports runtime paths
        provided by secret managers such as sops-nix.
      '';
      example = lib.literalExpression ''
        {
          PI_CODING_AGENT_DIR.value = "/home/user/.pi/agent";
          OPENAI_API_KEY.file = config.sops.secrets.openai-api-key.path;
        }
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Contents of `settings.json` in pi's agent configuration directory.
        The directory can be overridden with `environment.PI_CODING_AGENT_DIR`.
      '';
    };

    mcp = lib.mkOption {
      type = lib.types.attrsOf (pkgs.formats.json { }).type;
      default = { };
      description = ''
        Contents of `mcp.json` in pi's agent configuration directory, as an
        open-ended attribute set of JSON values matching pi's upstream format.
        Recursively merged into the file on each invocation.
        Declarative values override existing values; unmanaged entries are kept.
        Removing an entry here does not remove it from the file. An empty
        attribute set leaves the file untouched.

        The directory can be overridden with `environment.PI_CODING_AGENT_DIR`.
        Use pi's environment-variable or command references for credentials;
        literal values are stored in the world-readable Nix store.
      '';
      example = lib.literalExpression ''
        {
          mcpServers = {
            filesystem = {
              command = "npx";
              args = [ "-y" "@modelcontextprotocol/server-filesystem" "." ];
            };
            docs = {
              url = "https://example.com/mcp";
              headers.Authorization = "Bearer ''${DOCS_TOKEN}";
              exposure = "direct";
            };
          };
          autoEnableCodemode = false;
        }
      '';
    };

    finalRules = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      internal = true;
      readOnly = true;
    };

    finalArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      internal = true;
      readOnly = true;
    };

    finalPackage = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
    };
  };

  config = lib.setAttrByPath optionPath (
    let
      inherit (cfg)
        package
        jail
        models
        rules
        extensions
        skills
        themes
        promptTemplates
        extraArgs
        environment
        settings
        mcp
        ;

      pathFlags =
        flag: paths:
        lib.concatMap (path: [
          flag
          "${path}"
        ]) paths;

      rulesPath =
        if rules == null then
          null
        else if builtins.isPath rules then
          rules
        else
          pkgs.writeText "pi-AGENTS.md" rules;

      resourceArgs =
        (lib.optionals (rulesPath != null) [
          "--append-system-prompt"
          "${rulesPath}"
        ])
        ++ pathFlags "--skill" skills
        ++ pathFlags "--extension" extensions
        ++ pathFlags "--theme" themes
        ++ pathFlags "--prompt-template" promptTemplates;

      envPrelude = lib.optionalString (environment != null) (
        if lib.isAttrs environment && !lib.isDerivation environment then
          lib.concatLines (
            lib.mapAttrsToList (
              name: value: # bash
              if value ? file then
                ''
                  export ${lib.escapeShellArg name}="$(cat ${lib.escapeShellArg "${value.file}"})"
                ''
              else
                ''
                  export ${lib.escapeShellArg name}=${lib.escapeShellArg value.value}
                ''
            ) (lib.filterAttrs (_name: value: value != null) environment)
          )
        else
          ''
            set -a
            . ${lib.escapeShellArg "${environment}"}
            set +a
          ''
      );

      configDirPrelude = lib.optionalString (models != null || settings != { } || mcpPath != null) ''
        PI_CODING_AGENT_DIR="''${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
      '';

      jailConfigDirRuntime =
        let
          runtimeDefault = ''"''${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"'';
        in
        if
          environment != null
          && lib.isAttrs environment
          && !lib.isDerivation environment
          && environment.PI_CODING_AGENT_DIR != null
        then
          if environment.PI_CODING_AGENT_DIR ? file then
            ''
              agent_dir="$(cat ${lib.escapeShellArg "${environment.PI_CODING_AGENT_DIR.file}"})"
            ''
          else
            "agent_dir=${lib.escapeShellArg environment.PI_CODING_AGENT_DIR.value}"
        else if environment != null && (!lib.isAttrs environment || lib.isDerivation environment) then
          ''
            agent_dir="$(${pkgs.runtimeShell} -c '
              exec 3>&1
              set -a
              . ${lib.escapeShellArg "${environment}"} >&2
              set +a
              printf %s "''${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}" >&3
            ')"
          ''
        else
          "agent_dir=${runtimeDefault}";

      modelsPrelude =
        lib.optionalString (models != null) # bash
          ''
            if [ -L "$PI_CODING_AGENT_DIR/models.json" ]; then
              rm "$PI_CODING_AGENT_DIR/models.json"
            fi
            if [ ! -f "$PI_CODING_AGENT_DIR/models.json" ]; then
              mkdir -p "$PI_CODING_AGENT_DIR"
              install -m 0600 ${models} "$PI_CODING_AGENT_DIR/models.json"
            fi
          '';

      settingsPath =
        if settings == { } then null else pkgs.writeText "pi-settings.json" (builtins.toJSON settings);

      mcpPath = if mcp == { } then null else pkgs.writeText "pi-mcp.json" (builtins.toJSON mcp);

      mergeConfigPrelude =
        filename: patchPath:
        lib.optionalString (patchPath != null) # bash
          ''
            config_file="$PI_CODING_AGENT_DIR/${filename}"

            if [ -L "$config_file" ]; then
              rm "$config_file"
            fi

            mkdir -p "$PI_CODING_AGENT_DIR"
            tmp="$(mktemp "$PI_CODING_AGENT_DIR/${filename}.XXXXXX")"

            if [ -f "$config_file" ]; then
              ${lib.getExe pkgs.jq} -s '.[0] * .[1]' "$config_file" ${lib.escapeShellArg patchPath} > "$tmp"
            else
              printf '%s\n' '{}' | ${lib.getExe pkgs.jq} -s '.[0] * .[1]' - ${lib.escapeShellArg patchPath} > "$tmp"
            fi

            chmod 0600 "$tmp"

            if [ ! -f "$config_file" ] || ! cmp -s "$tmp" "$config_file"; then
              mv "$tmp" "$config_file"
            else
              rm "$tmp"
            fi
          '';

      argsStr = lib.concatMapStringsSep " " lib.escapeShellArg resourceArgs;
      extraArgsStr = lib.concatMapStringsSep " " lib.escapeShellArg extraArgs;

      wrapped =
        if
          resourceArgs == [ ]
          && environment == null
          && models == null
          && settingsPath == null
          && mcpPath == null
          && extraArgs == [ ]
        then
          package
        else
          pkgs.writeShellScriptBin "pi" # bash
            ''
              ${envPrelude}
              ${configDirPrelude}
              ${modelsPrelude}
              ${mergeConfigPrelude "settings.json" settingsPath}
              ${mergeConfigPrelude "mcp.json" mcpPath}

              case "''${1-}" in install|remove|uninstall|update|list|config|auth|mcp)
                  exec ${lib.escapeShellArg (lib.getExe package)} "$@"
                  ;;
                *)
                  exec ${lib.escapeShellArg (lib.getExe package)} ${argsStr} ${extraArgsStr} "$@"
                  ;;
              esac
            '';
    in
    {
      finalRules = rulesPath;
      finalArgs = resourceArgs ++ extraArgs;
      finalPackage =
        if jail.enable && !pkgs.stdenv.hostPlatform.isLinux then
          throw "pi.coding-agent.jail is supported only on Linux"
        else if jail.enable then
          let
            jailBuilder = jail-nix.lib.init pkgs;
            inherit (jailBuilder) combinators;
            configPermission = combinators.compose [
              (combinators.add-runtime ''
                ${jailConfigDirRuntime}
                case "$agent_dir" in
                  /*) ;;
                  *) agent_dir="$PWD/$agent_dir" ;;
                esac
                mkdir -p -- "$agent_dir"
                agent_dir_source="$(realpath "$agent_dir")"
                RUNTIME_ARGS+=(--bind "$agent_dir_source" "$agent_dir")
              '')
              (combinators.try-fwd-env "PI_CODING_AGENT_DIR")
            ];
            permissions = jail.permissions combinators ++ [ configPermission ];
          in
          jailBuilder "pi" wrapped permissions
        else
          wrapped;
    }
  );
}

{
  self,
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

    models = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a pi models.json file to install as the agent config's
        {file}`models.json` (default `~/.pi/agent/models.json`; see `configDir`).
      '';
      example = lib.literalExpression "./models.json";
    };

    rules = lib.mkOption {
      type = lib.types.nullOr lib.types.lines;
      default = null;
      description = ''
        Extra instructions to append to pi's system prompt via `--append-system-prompt`.
      '';
      example = ''
        # Rules
        - Be concise.
        - Make no mistakes.
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
      type = lib.types.nullOr (lib.types.either lib.types.path (lib.types.attrsOf lib.types.path));
      default = null;
      description = ''
        Extra environment to set before launching pi.

        This can either be a shell environment file that is sourced with `set -a`,
        or an attribute set mapping environment variable names to files whose contents
        should be exported as the variable values.
      '';
      example = lib.literalExpression ''
        {
          OPENAI_API_KEY = config.age.secrets.openai.path;
          ANTHROPIC_API_KEY = config.age.secrets.anthropic.path;
        }
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Contents of the agent config's settings.json (default ~/.pi/agent/settings.json; see configDir)";
    };

    configDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Directory pi uses for its agent config (settings.json, models.json,
        sessions, trust.json, etc.). When set, this is exported as
        `PI_CODING_AGENT_DIR` before launching pi, and the settings/models
        preludes write into this directory instead of the default
        `$HOME/.pi/agent/`.

        When null (the default), behavior is unchanged: pi uses
        `$HOME/.pi/agent` and the preludes write there as before.

        The string is expanded by the wrapper shell at runtime, so it may
        reference `$HOME` and other environment variables.
      '';
      example = "$HOME/.pi/agent";
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
        models
        rules
        extensions
        skills
        themes
        promptTemplates
        extraArgs
        environment
        settings
        configDir
        ;

      pathFlags =
        flag: paths:
        lib.concatMap (path: [
          flag
          "${path}"
        ]) paths;

      rulesPath = if rules == null then null else pkgs.writeText "pi-AGENTS.md" rules;

      resourceArgs =
        (lib.optionals (rulesPath != null) [
          "--append-system-prompt"
          "${rulesPath}"
        ])
        ++ pathFlags "--skill" skills
        ++ pathFlags "--extension" extensions
        ++ pathFlags "--theme" themes
        ++ pathFlags "--prompt-template" promptTemplates;

      envPaths = lib.optionalAttrs (lib.isAttrs environment) environment;

      agentDir = if configDir == null then "$HOME/.pi/agent" else configDir;

      configDirPrelude =
        lib.optionalString (configDir != null) ''
          export PI_CODING_AGENT_DIR="${configDir}"
        '';

      envPrelude = lib.optionalString (environment != null) (
        if lib.isAttrs environment then
          lib.concatLines (
            lib.mapAttrsToList (
              name: path: # bash
              ''
                export ${name}="$(cat ${lib.escapeShellArg "${path}"})"
              '') envPaths
          )
        else
          ''
            set -a
            . ${lib.escapeShellArg "${environment}"}
            set +a
          ''
      );

      modelsPrelude =
        lib.optionalString (models != null) # bash
          ''
            if [ -L "${agentDir}/models.json" ]; then
              rm "${agentDir}/models.json"
            fi
            if [ ! -f "${agentDir}/models.json" ]; then
              mkdir -p "${agentDir}"
              install -m 0600 ${models} "${agentDir}/models.json"
            fi
          '';

      settingsPath =
        if settings == { } then null else pkgs.writeText "pi-settings.json" (builtins.toJSON settings);

      settingsPrelude =
        lib.optionalString (settingsPath != null) # bash
          ''
            settings_file="${agentDir}/settings.json"

            if [ -L "$settings_file" ]; then
              rm "$settings_file"
            fi

            mkdir -p "${agentDir}"
            tmp="$(mktemp "${agentDir}/settings.json.XXXXXX")"

            if [ -f "$settings_file" ]; then
              ${lib.getExe pkgs.jq} -s '.[0] * .[1]' "$settings_file" ${lib.escapeShellArg settingsPath} > "$tmp"
            else
              printf '%s\n' '{}' | ${lib.getExe pkgs.jq} -s '.[0] * .[1]' - ${lib.escapeShellArg settingsPath} > "$tmp"
            fi

            chmod 0600 "$tmp"

            if [ ! -f "$settings_file" ] || ! cmp -s "$tmp" "$settings_file"; then
              mv "$tmp" "$settings_file"
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
          && extraArgs == [ ]
          && configDir == null
        then
          package
        else
          pkgs.writeShellScriptBin "pi" # bash
            ''
              ${configDirPrelude}
              ${envPrelude}
              ${modelsPrelude}
              ${settingsPrelude}

              case "''${1-}" in install|remove|uninstall|update|list|config)
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
      finalPackage = wrapped;
    }
  );
}

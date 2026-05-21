self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.pi.coding-agent;
in
{
  imports = [
    (import ./options.nix {
      inherit self;
      optionPath = [
        "programs"
        "pi"
        "coding-agent"
      ];
    })
  ];

  options.programs.pi.coding-agent = {
    enable = lib.mkEnableOption "pi agent";

    models = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a pi models.json file to install as
        {file}`~/.pi/agent/models.json` for the selected users.
      '';
      example = lib.literalExpression "./models.json";
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      defaultText = lib.literalExpression "[ ] (interpreted as all normal users)";
      description = ''
        Normal users whose `~/.pi/agent` should be managed.

        An empty list means all normal users.
      '';
      example = [ "lukas" ];
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.systemPackages = [ cfg.finalPackage ];
      }

      (lib.mkIf (cfg.models != null) (
        let
          rules = [
            "d %h/.pi 0700 - - -"
            "d %h/.pi/agent 0700 - - -"
            "L+ %h/.pi/agent/models.json - - - - ${cfg.models}"
          ];
        in
        lib.mkMerge [
          (lib.mkIf (cfg.users == [ ]) {
            systemd.user.tmpfiles.rules = rules;
          })
          (lib.mkIf (cfg.users != [ ]) {
            systemd.user.tmpfiles.users = builtins.listToAttrs (
              map (name: {
                inherit name;
                value.rules = rules;
              }) cfg.users
            );
          })
        ]
      ))
    ]
  );
}

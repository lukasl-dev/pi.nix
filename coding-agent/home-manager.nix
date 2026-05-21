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
        {file}`~/.pi/agent/models.json`.
      '';
      example = lib.literalExpression "./models.json";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.packages = [ cfg.finalPackage ];
      }

      (lib.mkIf (cfg.models != null) {
        home.file.".pi/agent/models.json".source = cfg.models;
      })
    ]
  );
}

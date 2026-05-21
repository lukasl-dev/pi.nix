{ self, lib }:

{
  mkCodingAgent =
    {
      pkgs,
      modules ? [ ],
      extraSpecialArgs ? { },
    }:
    let
      evaluated = lib.evalModules {
        specialArgs = {
          inherit self pkgs;
        }
        // extraSpecialArgs;

        modules = [ (import ./options.nix { inherit self; }) ] ++ modules;
      };

      inherit (evaluated.config.pi.coding-agent) finalPackage finalRules finalArgs;
    in
    {
      inherit (evaluated) config options;
      coding-agent = finalPackage;
      package = finalPackage;
      rules = finalRules;
      args = finalArgs;
    };
}

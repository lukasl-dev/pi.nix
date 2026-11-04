{ pkgs }:

# Temporary downstream workarounds, applied in the extracted upstream source
# before generating lockfiles. Remove each block once upstream makes it redundant.
pkgs.writeShellApplication {
  name = "pi-patch";
  text = # bash
    ''
      # nothing to patch here
      :
    '';
}

{ pkgs, patch }:

pkgs.writeShellApplication {
  name = "pi-regenerate-models";
  runtimeInputs = with pkgs; [
    coreutils
    jq
    nix
    nodejs
    patch
  ];
  text = # bash
    ''
      set -euo pipefail

      tmpdir=$(mktemp -d)
      trap 'rm -rf "$tmpdir"' EXIT

      rev=$(jq -r .rev VERSION.json)
      expected_hash=$(jq -r .hash VERSION.json)
      source=$(nix store prefetch-file --json --unpack \
        "https://github.com/earendil-works/pi/archive/refs/tags/$rev.tar.gz")
      [[ "$(jq -r .hash <<< "$source")" == "$expected_hash" ]]
      src=$(jq -r .storePath <<< "$source")

      cp -R "$src"/. "$tmpdir"
      chmod -R u+w "$tmpdir"
      cp package-lock.json "$tmpdir/package-lock.json"

      pushd "$tmpdir" >/dev/null
      pi-patch
      npm ci --ignore-scripts --no-audit

      npm run generate-models --workspace=packages/ai
      npm run check:model-data --workspace=packages/ai
      popd >/dev/null

      generated="$tmpdir/packages/ai/src"
      output="$tmpdir/pi-nix-ai"
      mkdir -p "$output/providers"
      cp "$generated/models.generated.ts" "$output/"
      cp "$generated/providers"/*.models.ts "$output/providers/"
      cp -R "$generated/providers/data" "$output/providers/"

      rm -rf ai
      mv "$output" ai
      echo "Updated generated AI model data for $rev"
    '';
}

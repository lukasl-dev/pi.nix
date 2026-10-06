{
  pkgs,
  bun2nix,
  patch,
}:

pkgs.writeShellApplication {
  name = "pi-sync";
  runtimeInputs = with pkgs; [
    bun
    coreutils
    findutils
    gawk
    git
    gnugrep
    gnused
    jq
    nix
    nodejs
    npm-lockfile-fix
    prefetch-npm-deps
    bun2nix
    patch
  ];
  text = # bash
    ''
      set -euo pipefail

      tmpdir=$(mktemp -d)
      trap 'rm -rf "$tmpdir"' EXIT

      rev=$(git ls-remote --tags --refs https://github.com/earendil-works/pi.git 'v*' \
        | awk -F/ '{print $3}' \
        | grep -E '^v[0-9]+(\.[0-9]+)*$' \
        | sort -V \
        | tail -n1)
      [[ -n "$rev" ]]

      source=$(nix store prefetch-file --json --unpack \
        "https://github.com/earendil-works/pi/archive/refs/tags/$rev.tar.gz")
      hash=$(jq -r .hash <<< "$source")
      src=$(jq -r .storePath <<< "$source")

      cp -R "$src"/. "$tmpdir"
      chmod -R u+w "$tmpdir"
      npm-lockfile-fix "$tmpdir/package-lock.json"

      # bun2nix supports lockfile version 1; Bun preserves it when updating.
      cp bun.lock "$tmpdir/bun.lock"

      # Bun updates workspace versions but leaves their dependency ranges at the
      # previous release in the seeded lockfile. For example, when updating to
      # v0.87.0, "@earendil-works/pi-ai": "^0.86.1" must become "^0.87.0".
      # Otherwise the mismatch triggers dependency re-resolution in the
      # network-isolated Nix build.
      previous_version=$(jq -r '.rev | ltrimstr("v")' VERSION.json)
      if [[ "$previous_version" != "''${rev#v}" ]]; then
        sed -Ei "s#(\"@earendil-works/[^\"]+\": \"\^)''${previous_version//./\\.}(\")#\1''${rev#v}\2#g" "$tmpdir/bun.lock"
      fi

      pushd "$tmpdir" >/dev/null
      pi-patch

      npm dedupe --package-lock-only --ignore-scripts
      # Apply available fixes; the scoped security scans below own the gate.
      # audit-level=none allows remaining advisories, not npm command failures.
      npm audit fix --package-lock-only --ignore-scripts --audit-level=none
      node scripts/generate-coding-agent-install-lock.mjs

      bun install --ignore-scripts
      # Bun has no audit-level=none. Reuse only the workspace exceptions;
      # registry/install errors and other remaining advisories still fail.
      # Exact-pin fixes can rewrite manifests, which our pristine-source builds
      # cannot reproduce. Require an explicit source patch for those changes.
      find . -name node_modules -prune -o -type f -name package.json -print0 \
        | sort -z | xargs -0 sha256sum > "$tmpdir/manifests.sha256"
      bun audit fix --lockfile-only --ignore-scripts ${
        pkgs.lib.concatMapStringsSep " " (
          advisory: "--ignore " + pkgs.lib.escapeShellArg advisory.id
        ) (pkgs.lib.importTOML ./osv-scanner-workspace.toml).IgnoredVulns
      }
      if ! sha256sum --check --status "$tmpdir/manifests.sha256"; then
        echo "Bun audit fix changed package manifests; an explicit source patch is required" >&2
        exit 1
      fi
      bun2nix -o bun.nix
      popd >/dev/null

      sed -i '/^  fetchurl,$/a\  workspaceRoot ? throw "coding-agent/bun.nix requires workspaceRoot (the upstream pi source root)",' "$tmpdir/bun.nix"
      sed -Ei 's|copyPathToStore \.\/packages\/([^ );]+)|copyPathToStore (workspaceRoot + "/packages/\1")|g' "$tmpdir/bun.nix"

      npm_deps_hash=$(prefetch-npm-deps "$tmpdir/package-lock.json" | tail -n1)

      jq \
        --arg rev "$rev" \
        --arg hash "$hash" \
        --arg npmDepsHash "$npm_deps_hash" \
        '.rev = $rev | .hash = $hash | .projects["coding-agent"].npmDepsHash = $npmDepsHash' \
        VERSION.json > "$tmpdir/VERSION.json"

      cp "$tmpdir/package-lock.json" package-lock.json
      cp "$tmpdir/bun.lock" bun.lock
      cp "$tmpdir/bun.nix" coding-agent/bun.nix
      mkdir -p coding-agent/install-lock
      cp "$tmpdir/packages/coding-agent/install-lock/"*.json coding-agent/install-lock/
      cp "$tmpdir/VERSION.json" VERSION.json
      echo "Updated lockfiles and VERSION.json for $rev"
    '';
}

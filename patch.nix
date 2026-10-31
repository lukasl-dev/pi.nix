{ pkgs }:

# Temporary downstream workarounds, applied in the extracted upstream source
# before generating lockfiles. Remove each block once upstream makes it redundant.
pkgs.writeShellApplication {
  name = "pi-patch";
  runtimeInputs = with pkgs; [
    gnugrep
    gnused
    findutils
  ];
  text = # bash
    ''
      # Remove each override when a Pi release contains the corresponding fix.
      # The expected old pins make an upstream change stop the update for review.
      # Undici 8.12.2 fixes the reported runtime advisories.
      grep -q '"undici": "8.10.2"' packages/coding-agent/package.json
      sed -i 's/"undici": "8.10.2"/"undici": "8.12.3"/' packages/coding-agent/package.json

      # Upstream replaced shx and updated minimatch to fix GHSA-g3hv-75wg-m249.
      # Remove these overrides when a release includes those changes.
      grep -q '"minimatch": "10.2.6"' packages/coding-agent/package.json
      grep -q '"shx": "0.3.4"' package.json
      sed -i 's/"minimatch": "10.2.6"/"minimatch": "11.0.3"/' packages/coding-agent/package.json
      sed -i 's/"shx": "0.3.4"/"shx": "0.4.0"/' package.json
      find packages -name node_modules -prune -o -name package.json -type f -exec \
        sed -i 's/"shx": "0.3.4"/"shx": "0.4.0"/g' {} +

      # Plugin 1.4.9 includes fixed Miniflare/undici and Zod; Vitest 4.1.12
      # fixes the mocker advisories.
      grep -q '"@cloudflare/vitest-plugin": "1.4.4"' packages/durable/package.json
      grep -q '"vitest": "4.1.11"' packages/durable/package.json
      sed -i 's/"@cloudflare\/vitest-plugin": "1.4.4"/"@cloudflare\/vitest-plugin": "1.4.9"/' packages/durable/package.json
      find packages -name node_modules -prune -o -name package.json -type f -exec \
        sed -i 's/"vitest": "4.1.11"/"vitest": "4.1.12"/g' {} +
    '';
}

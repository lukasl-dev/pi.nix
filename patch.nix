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

      # Plugin 1.4.9 includes fixed Miniflare/undici and Zod; Vitest 4.1.12
      # fixes the mocker advisories.
      grep -q '"@cloudflare/vitest-plugin": "1.4.4"' packages/durable/package.json
      grep -q '"vitest": "4.1.11"' packages/durable/package.json
      sed -i 's/"@cloudflare\/vitest-plugin": "1.4.4"/"@cloudflare\/vitest-plugin": "1.4.9"/' packages/durable/package.json
      find packages -name node_modules -prune -o -name package.json -type f -exec \
        sed -i 's/"vitest": "4.1.11"/"vitest": "4.1.12"/g' {} +
    '';
}

{
  buildNpmPackage,
  nodejs,
  callPackage,
  src,
  version,
  npmDepsHash,
  patch,
}:
let
  workspacePackages = buildNpmPackage {
    pname = "pi-coding-agent-workspace";
    inherit src version npmDepsHash;

    # Native example dependencies such as canvas are not used by the build.
    npmRebuildFlags = [ "--ignore-scripts" ];

    postPatch = ''
      ${patch}/bin/pi-patch
      cp ${../package-lock.json} package-lock.json
    '';

    preBuild = ''
      find packages -name "package.json" -exec sed -i \
        -e 's/--watch --preserveWatchOutput//g' \
        {} \;

      for f in packages/ai/src/models.ts packages/agent/src/agent.ts packages/tui/src/utils.ts; do
        [ -f "$f" ] && echo '// @ts-nocheck' | cat - "$f" > tmp && mv tmp "$f"
      done

      changelogReplacement='`https://github.com/earendil-works/pi/blob/v''${newVersion}/packages/coding-agent/CHANGELOG.md`'
      for changelogUrl in \
        '"https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/CHANGELOG.md"' \
        '"https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/CHANGELOG.md"'
      do
        if grep -qF "$changelogUrl" packages/coding-agent/src/modes/interactive/interactive-mode.ts; then
          substituteInPlace packages/coding-agent/src/modes/interactive/interactive-mode.ts \
            --replace-fail "$changelogUrl" "$changelogReplacement"
        fi
      done

      cp ${../ai/models.generated.ts} packages/ai/src/models.generated.ts
      cp -R ${../ai/providers}/. packages/ai/src/providers/

      substituteInPlace packages/ai/package.json \
        --replace-fail 'npm run generate-models && ' '''
    '';

    buildPhase = ''
      runHook preBuild
      npm run build:offline
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      ${builtins.readFile ./pack.sh}
      runHook postInstall
    '';

  };
in
callPackage ./runtime.nix {
  inherit workspacePackages version;
  pname = "pi-coding-agent";
  runtime = nodejs;
  cli = "dist/bundle/cli.js";
}

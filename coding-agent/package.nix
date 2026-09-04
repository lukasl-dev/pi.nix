{
  lib,
  stdenv,
  buildNpmPackage,
  makeWrapper,
  nodejs,
  typescript,
  typescript-go,
  pkg-config,
  pixman,
  cairo,
  pango,
  libpng,
  libjpeg,
  giflib,
  librsvg,
  fd,
  gitMinimal,
  openssh,
  ripgrep,
  src,
  version,
  npmDepsHash,
}:
let
  runtimeBins = lib.makeBinPath [
    nodejs
    gitMinimal
    openssh # required for git SSH clones
    ripgrep
    fd
  ];
in
buildNpmPackage {
  pname = "pi-coding-agent";
  inherit src version npmDepsHash;

  nativeBuildInputs = [
    makeWrapper
    pkg-config
    typescript
    typescript-go
  ];

  buildInputs = [
    pixman
    cairo
    pango
    libpng
    libjpeg
    giflib
    librsvg
    fd
  ];

  postPatch = ''
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
    mkdir -p $out/bin $out/lib/node_modules/@earendil-works

    for pkg in tui telemetry ai agent protocol client coding-agent mom pods; do
      [ -d "packages/$pkg/dist" ] || continue
      mkdir -p "$out/lib/node_modules/@earendil-works/pi-$pkg"
      cp -r packages/$pkg/dist/* "$out/lib/node_modules/@earendil-works/pi-$pkg/"
      cp packages/$pkg/package.json "$out/lib/node_modules/@earendil-works/pi-$pkg/"
    done

    cp -rL node_modules/. "$out/lib/node_modules/"

    makeWrapper ${nodejs}/bin/node $out/bin/pi \
      --add-flags "$out/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js" \
      --set PI_PACKAGE_DIR "$out/lib/node_modules/@earendil-works/pi-coding-agent" \
      --prefix NODE_PATH : "$out/lib/node_modules" \
      --suffix PATH : "${runtimeBins}" \
      --run 'export NPM_CONFIG_PREFIX="''${NPM_CONFIG_PREFIX:-''${XDG_DATA_HOME:-$HOME/.local/share}/pi/npm}"'
    runHook postInstall
  '';

  meta = {
    description = "Pi - a minimal terminal coding harness";
    homepage = "https://github.com/earendil-works/pi";
    license = lib.licenses.mit;
    mainProgram = "pi";
    maintainers = [
      {
        name = "Lukas";
        email = "me@lukasl.dev";
        github = "lukasl-dev";
      }
    ];
  };
}

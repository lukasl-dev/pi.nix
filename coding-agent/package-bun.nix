{
  lib,
  stdenv,
  bun2nix,
  bun,
  makeWrapper,
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
}:
let
  runtimeBins = lib.makeBinPath [
    gitMinimal
    openssh # required for git SSH clones
    ripgrep
    fd
  ];

  bunInstallFlags =
    if stdenv.hostPlatform.isDarwin then
      [
        "--linker=hoisted"
        "--backend=copyfile"
        "--frozen-lockfile"
      ]
    else
      [
        "--linker=hoisted"
        "--frozen-lockfile"
      ];
in
stdenv.mkDerivation {
  pname = "pi-coding-agent-bun";
  inherit src version bunInstallFlags;

  nativeBuildInputs = [
    bun2nix.hook
    bun
    makeWrapper
    pkg-config
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

  bunDeps = bun2nix.fetchBunDeps {
    bunNix =
      {
        copyPathToStore,
        fetchFromGitHub,
        fetchgit,
        fetchurl,
        ...
      }@args:
      import ./bun.nix (args // { workspaceRoot = src; });
  };

  dontRunLifecycleScripts = true;

  postPatch = ''
    cp ${../bun.lock} bun.lock
  '';

  preBuild = ''
        find packages -name "package.json" -exec sed -i \
          -e 's/--watch --preserveWatchOutput//g' \
          {} \;

        for f in packages/ai/src/models.ts packages/agent/src/agent.ts packages/tui/src/utils.ts; do
          [ -f "$f" ] && echo '// @ts-nocheck' | cat - "$f" > tmp && mv tmp "$f"
        done

        changelogReplacement='`https://github.com/earendil-works/pi/blob/v${version}/packages/coding-agent/CHANGELOG.md`'
        for changelogUrl in \
          '"https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/CHANGELOG.md"' \
          '"https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/CHANGELOG.md"'
        do
          if grep -qF "$changelogUrl" packages/coding-agent/src/modes/interactive/interactive-mode.ts; then
            substituteInPlace packages/coding-agent/src/modes/interactive/interactive-mode.ts \
              --replace-fail "$changelogUrl" "$changelogReplacement"
          fi
        done

        cp ${../models.generated.ts} packages/ai/src/models.generated.ts

        substituteInPlace packages/ai/package.json \
          --replace-fail 'npm run generate-models && ' '''

        cat > patch-package-json.js <<'BUN'
    const fs = require('fs');
    for (const file of ['packages/ai/package.json', 'packages/coding-agent/package.json']) {
      const pkg = JSON.parse(fs.readFileSync(file, 'utf8'));
      for (const [name, script] of Object.entries(pkg.scripts ?? {})) {
        pkg.scripts[name] = script.replaceAll('npm run ', 'bun run ');
      }
      fs.writeFileSync(file, JSON.stringify(pkg, null, 2) + '\n');
    }
    BUN
        bun patch-package-json.js
        rm patch-package-json.js
  '';

  buildPhase = ''
    runHook preBuild
    for pkg in tui ai agent coding-agent; do
      (cd "packages/$pkg" && bun run build)
    done
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib/node_modules/@earendil-works

    for pkg in tui ai agent coding-agent mom pods; do
      [ -d "packages/$pkg/dist" ] || continue
      mkdir -p "$out/lib/node_modules/@earendil-works/pi-$pkg"
      cp -r packages/$pkg/dist/* "$out/lib/node_modules/@earendil-works/pi-$pkg/"
      cp packages/$pkg/package.json "$out/lib/node_modules/@earendil-works/pi-$pkg/"
    done

    cp -rL node_modules/. "$out/lib/node_modules/"

    makeWrapper ${bun}/bin/bun $out/bin/pi \
      --add-flags "$out/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js" \
      --set PI_PACKAGE_DIR "$out/lib/node_modules/@earendil-works/pi-coding-agent" \
      --prefix NODE_PATH : "$out/lib/node_modules" \
      --suffix PATH : "${runtimeBins}" \
      --run 'export NPM_CONFIG_PREFIX="''${NPM_CONFIG_PREFIX:-''${XDG_DATA_HOME:-$HOME/.local/share}/pi/npm}"'
    runHook postInstall
  '';

  meta = {
    description = "Pi - a minimal terminal coding harness (built with Bun)";
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

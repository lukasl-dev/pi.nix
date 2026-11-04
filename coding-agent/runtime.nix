{
  lib,
  stdenv,
  importNpmLock,
  nodejs,
  autoPatchelfHook,
  libxcb,
  makeWrapper,
  fd,
  gitMinimal,
  openssh,
  ripgrep,
  workspacePackages,
  runtime,
  pname,
  version,
  cli,
}:
let
  installPackage = lib.importJSON ./install-lock/package.json;
  installLock = lib.importJSON ./install-lock/package-lock.json;
  packageSourceOverrides = {
    "node_modules/@earendil-works/chord" = workspacePackages + "/chord.tgz";
    "node_modules/@earendil-works/pi-agent-core" = workspacePackages + "/agent.tgz";
    "node_modules/@earendil-works/pi-ai" = workspacePackages + "/ai.tgz";
    "node_modules/@earendil-works/pi-codemode" = workspacePackages + "/codemode.tgz";
    "node_modules/@earendil-works/pi-mcp" = workspacePackages + "/mcp.tgz";
    "node_modules/@earendil-works/pi-schema" = workspacePackages + "/schema.tgz";
    "node_modules/@earendil-works/pi-telemetry" = workspacePackages + "/telemetry.tgz";
    "node_modules/@earendil-works/pi-tui" = workspacePackages + "/tui.tgz";
    "node_modules/@earendil-works/pi-coding-agent" = workspacePackages + "/coding-agent.tgz";
  };
  internalPackages = builtins.filter (
    path: builtins.match "node_modules/@earendil-works/[^/]+" path != null
  ) (builtins.attrNames installLock.packages);
  runtimeBins = lib.makeBinPath [
    runtime
    nodejs # Pi uses npm to manage extension packages, also under Bun.
    gitMinimal
    openssh
    ripgrep
    fd
  ];
in
assert lib.assertMsg (installPackage.version == version) "pi runtime lock must match VERSION.json";
assert lib.assertMsg (lib.all (path: builtins.hasAttr path packageSourceOverrides)
  internalPackages
) "Every internal runtime package must be packed from this checkout, not fetched from npm";
stdenv.mkDerivation {
  inherit pname version;
  src = ./install-lock;

  npmDeps = importNpmLock {
    npmRoot = ./install-lock;
    inherit packageSourceOverrides;
  };
  npmRebuildFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [
    nodejs
    importNpmLock.npmConfigHook
    makeWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = [
    nodejs
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib
    libxcb
  ];

  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib/node_modules
    cp -rL node_modules/. $out/lib/node_modules/
    # npm's hidden lock records the build-time tarball store paths; retaining it
    # would pull those sources and the packed build output into the closure.
    rm -f $out/lib/node_modules/.package-lock.json

    makeWrapper ${runtime}/bin/${runtime.meta.mainProgram} $out/bin/pi \
      --add-flags "$out/lib/node_modules/@earendil-works/pi-coding-agent/${cli}" \
      --set PI_PACKAGE_DIR "$out/lib/node_modules/@earendil-works/pi-coding-agent" \
      --prefix NODE_PATH : "$out/lib/node_modules" \
      --suffix PATH : "${runtimeBins}" \
      --run 'export NPM_CONFIG_PREFIX="''${NPM_CONFIG_PREFIX:-''${XDG_DATA_HOME:-$HOME/.local/share}/pi/npm}"'
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ runtime ];
  installCheckPhase = ''
    runHook preInstallCheck
    test "$("$out/bin/pi" --version)" = "${version}"
    PATH="${runtimeBins}" ${runtime}/bin/${runtime.meta.mainProgram} ${./runtime-check.mjs} "$out/lib/node_modules"
    runHook postInstallCheck
  '';

  passthru = { inherit workspacePackages; };
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

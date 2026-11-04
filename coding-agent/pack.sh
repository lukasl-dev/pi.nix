# Pack only the public package contents, including docs, examples and native TUI
# helpers. The build workspace and its node_modules never enter the output.
mkdir -p "$out"
export npm_config_cache="$TMPDIR/pack-cache"
for pkg in chord telemetry schema ai tui agent codemode mcp coding-agent; do
  tarball=$(cd "packages/$pkg" && npm pack --ignore-scripts --loglevel=error --pack-destination "$TMPDIR")
  mv "$TMPDIR/$tarball" "$out/$pkg.tgz"
done

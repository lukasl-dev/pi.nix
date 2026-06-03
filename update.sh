#!/usr/bin/env -S nix shell nixpkgs#bash nixpkgs#bun nixpkgs#git nixpkgs#jq nixpkgs#nix nixpkgs#nodejs nixpkgs#npm-lockfile-fix nixpkgs#prefetch-npm-deps -c bash
# shellcheck shell=bash
set -euo pipefail

repo_url=https://github.com/earendil-works/pi.git
archive_base_url=https://github.com/earendil-works/pi/archive/refs/tags
version_file=VERSION.json
models_file=models.generated.ts
package_lock_file=package-lock.json
bun_lock_file=bun.lock
bun_nix_file=coding-agent/bun.nix
bun2nix_version=2.1.0

die() {
	echo "$*" >&2
	exit 1
}
out() { [[ -n ${GITHUB_OUTPUT:-} ]] && echo "$1=$2" >>"$GITHUB_OUTPUT" || true; }

write_version_json() {
	local rev=$1 hash=$2 npm_deps_hash=$3 tmp
	tmp=$(mktemp)
	jq \
		--arg rev "$rev" \
		--arg hash "$hash" \
		--arg npmDepsHash "$npm_deps_hash" \
		'.rev = $rev
    | .hash = $hash
    | .projects["coding-agent"].npmDepsHash = $npmDepsHash' \
		"$version_file" >"$tmp"
	mv "$tmp" "$version_file"
}

validate_package_lock() {
	local lockfile=$1 missing
	missing=$(jq -r '
    .packages
    | to_entries[]
    | select(.key | contains("node_modules/"))
    | select((.value.link // false) | not)
    | select(((.value | has("resolved")) | not) or ((.value | has("integrity")) | not))
    | .key
  ' "$lockfile")

	if [[ -n "$missing" ]]; then
		echo "package-lock.json still has incomplete package entries:" >&2
		echo "$missing" >&2
		exit 1
	fi
}

rewrite_bun_nix() {
	local file=$1
	node - "$file" <<'NODE'
const fs = require('fs');
const file = process.argv[2];
let text = fs.readFileSync(file, 'utf8');
text = text.replace(
  '  fetchurl,\n  ...',
  '  fetchurl,\n  workspaceRoot ? throw "coding-agent/bun.nix requires workspaceRoot (the upstream pi source root)",\n  ...'
);
text = text.replace(
  /copyPathToStore (\.\/packages\/[^\s);]+)/g,
  (_, relPath) => `copyPathToStore (workspaceRoot + "${relPath.slice(1)}")`
);
fs.writeFileSync(file, text);
NODE
}

latest_tag() {
	git ls-remote --tags --refs "$repo_url" 'v*' |
		awk -F/ '{print $3}' |
		grep -E '^v[0-9]+(\.[0-9]+)*$' |
		sort -V |
		tail -n1
}

cleanup() {
	rm -rf "$tmpdir" "$backup_dir"
}

restore_file() {
	local path=$1
	if [[ -f "$backup_dir/$path" ]]; then
		mkdir -p "$(dirname "$path")"
		cp "$backup_dir/$path" "$path" 2>/dev/null || true
	else
		rm -f "$path"
		if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
			git reset -q -- "$path" 2>/dev/null || true
		fi
	fi
}

restore_and_cleanup() {
	local status=$?
	if ((status != 0)); then
		restore_file "$version_file"
		restore_file "$models_file"
		restore_file "$package_lock_file"
		restore_file "$bun_lock_file"
		restore_file "$bun_nix_file"
	fi
	cleanup
	exit "$status"
}

current_rev=$(jq -r '.rev' "$version_file")
latest_rev=$(latest_tag)
[[ -n "$latest_rev" ]] || die "Failed to determine latest upstream tag"

target_rev=$current_rev
version_changed=false
if [[ "$latest_rev" != "$current_rev" ]]; then
	target_rev=$latest_rev
	version_changed=true
fi

tmpdir=$(mktemp -d)
backup_dir=$(mktemp -d)
for path in "$version_file" "$models_file" "$package_lock_file" "$bun_lock_file" "$bun_nix_file"; do
	if [[ -f "$path" ]]; then
		mkdir -p "$backup_dir/$(dirname "$path")"
		cp "$path" "$backup_dir/$path"
	fi
done
trap restore_and_cleanup EXIT

archive_url="$archive_base_url/$target_rev.tar.gz"
prefetch_json=$(nix store prefetch-file --json --unpack "$archive_url")
src_hash=$(jq -r .hash <<<"$prefetch_json")
src_path=$(jq -r .storePath <<<"$prefetch_json")

cp -R "$src_path"/. "$tmpdir"/
chmod -R u+w "$tmpdir"
[[ -f "$tmpdir/package-lock.json" ]] || die "Upstream archive does not contain package-lock.json"

cp "$tmpdir/package-lock.json" "$package_lock_file"
npm-lockfile-fix "$package_lock_file"
validate_package_lock "$package_lock_file"
cp "$package_lock_file" "$tmpdir/package-lock.json"

package_lock_changed=false
if [[ ! -f "$backup_dir/$package_lock_file" ]] || ! cmp -s "$package_lock_file" "$backup_dir/$package_lock_file"; then
	package_lock_changed=true
fi

echo "Generating Bun lockfiles for $target_rev..."
pushd "$tmpdir" >/dev/null
bun install --ignore-scripts
bunx bun2nix@${bun2nix_version} -o bun.nix
popd >/dev/null
rewrite_bun_nix "$tmpdir/bun.nix"

bun_lock_changed=false
if [[ ! -f "$backup_dir/$bun_lock_file" ]] || ! cmp -s "$tmpdir/bun.lock" "$backup_dir/$bun_lock_file"; then
	cp "$tmpdir/bun.lock" "$bun_lock_file"
	bun_lock_changed=true
fi

bun_nix_changed=false
if [[ ! -f "$backup_dir/$bun_nix_file" ]] || ! cmp -s "$tmpdir/bun.nix" "$backup_dir/$bun_nix_file"; then
	cp "$tmpdir/bun.nix" "$bun_nix_file"
	bun_nix_changed=true
fi

# Nix flakes ignore untracked files. Mark newly generated files as intent-to-add
# so local flake builds can see them before the final workflow commit step.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	git add --intent-to-add -- "$package_lock_file" "$bun_lock_file" "$bun_nix_file"
fi

echo "Generating model definitions for $target_rev..."
pushd "$tmpdir" >/dev/null
export NPM_CONFIG_YES=true
npm ci --ignore-scripts
npm run generate-models --workspace=packages/ai
popd >/dev/null

generated_models="$tmpdir/packages/ai/src/models.generated.ts"
[[ -f "$generated_models" ]] || die "Model generation did not produce $generated_models"

models_changed=false
if cmp -s "$generated_models" "$models_file"; then
	echo "models.generated.ts is already up to date"
else
	cp "$generated_models" "$models_file"
	models_changed=true
	echo "Updated models.generated.ts"
fi

if [[ "$version_changed" == "true" ]]; then
	npm_deps_hash=$(prefetch-npm-deps "$package_lock_file" | tail -n1)
	[[ -n "$npm_deps_hash" ]] || die "Failed to determine npmDepsHash"
	write_version_json "$target_rev" "$src_hash" "$npm_deps_hash"
fi

if [[ 
	"$version_changed" == "true" ||
	"$models_changed" == "true" ||
	"$package_lock_changed" == "true" ||
	"$bun_lock_changed" == "true" ||
	"$bun_nix_changed" == "true" ]] \
	; then
	nix build .#coding-agent --no-link >/dev/null
	nix build .#coding-agent-bun --no-link >/dev/null
fi

if [[ "$version_changed" == "true" ]]; then
	echo "Updated VERSION.json to $target_rev"
elif [[ "$models_changed" == "true" ]]; then
	echo "Updated models for $target_rev"
elif [[ "$package_lock_changed" == "true" || "$bun_lock_changed" == "true" || "$bun_nix_changed" == "true" ]]; then
	echo "Updated lockfiles for $target_rev"
else
	echo "VERSION.json already points to $current_rev"
	echo "No changes to commit"
fi

out version "$target_rev"
out version_changed "$version_changed"
out models_changed "$models_changed"
out package_lock_changed "$package_lock_changed"
out bun_lock_changed "$bun_lock_changed"
out bun_nix_changed "$bun_nix_changed"

trap - EXIT
cleanup

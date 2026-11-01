#!/usr/bin/env bash
set -euo pipefail

action=${1:?expected check or publish}
lane=${2:?expected package or models}
case "$lane" in
  package)
    paths=(
      VERSION.json
      package-lock.json
      bun.lock
      coding-agent/bun.nix
      coding-agent/install-lock
    )
    ;;
  models)
    paths=(ai)
    ;;
  *)
    echo "Unknown lane: $lane" >&2
    exit 1
    ;;
esac

listing=$(mktemp)
trap 'rm -f "$listing"' EXIT
{
  git diff --name-only --no-renames -z
  git diff --cached --name-only --no-renames -z
  git ls-files --others -z
} > "$listing"

changed=false
while IFS= read -r -d '' path; do
  case "$lane:$path" in
    package:VERSION.json | package:package-lock.json | package:bun.lock | \
      package:coding-agent/bun.nix | package:coding-agent/install-lock/* | models:ai/*)
      ;;
    *)
      printf 'Unexpected changed path: %q\n' "$path" >&2
      exit 1
      ;;
  esac
  changed=true
done < "$listing"

if [[ "$action" == check ]]; then
  exit 0
fi
if [[ "$action" != publish ]]; then
  echo "Unknown action: $action" >&2
  exit 1
fi
if [[ "$changed" == false ]]; then
  echo 'No changes to publish'
  exit 0
fi

: "${BASE:?}" "${BRANCH:?}"
if [[ $(git rev-parse HEAD) != "$BASE" ]]; then
  echo 'Local HEAD changed' >&2
  exit 1
fi

git config user.name 'github-actions[bot]'
git config user.email 'github-actions[bot]@users.noreply.github.com'
git add -A -- "${paths[@]}"

tag=
if [[ "$lane" == models ]]; then
  git commit -m 'Update models'
else
  : "${PREVIOUS_VERSION:?}"
  version=$(jq -er .rev VERSION.json)
  if [[ "$version" != "$PREVIOUS_VERSION" ]]; then
    git commit -m "Update pi to $version"
    if [[ -z $(git ls-remote --tags --refs origin "refs/tags/$version") ]]; then
      git tag -a "$version" -m "$version"
      tag="refs/tags/$version"
    fi
  else
    git commit -m 'Update lockfiles'
  fi
fi

if [[ -n $(git status --porcelain --untracked-files=all --ignored) ]]; then
  echo 'Updater left uncommitted changes' >&2
  exit 1
fi
if [[ $(git rev-parse HEAD^) != "$BASE" ]]; then
  echo 'Update is not a direct child of the validated base' >&2
  exit 1
fi

remote=$(git ls-remote --exit-code origin "refs/heads/$BRANCH")
if [[ "$remote" != "$BASE"$'\t'"refs/heads/$BRANCH" ]]; then
  echo 'Default branch advanced; rerun the update' >&2
  exit 1
fi

# The direct-child check permits only a fast-forward; the explicit lease also
# rejects a concurrent reset between the remote check and the push handshake.
lease="--force-with-lease=refs/heads/$BRANCH:$BASE"
if [[ -n "$tag" ]]; then
  git push --atomic "$lease" origin "HEAD:refs/heads/$BRANCH" "$tag:$tag"
else
  git push "$lease" origin "HEAD:refs/heads/$BRANCH"
fi

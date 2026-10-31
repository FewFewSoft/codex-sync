#!/usr/bin/env bash
set -euo pipefail
fail() {
	printf 'Error: %s\n' "$*" >&2
	exit 1
}
[[ $# -le 1 ]] || fail 'Usage: ./release.sh [major|minor|patch]'
level=${1:-}
case $level in '' | major | minor | patch) ;; *) fail 'Usage: ./release.sh [major|minor|patch]' ;; esac
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
cd -- "$base"
command -v git >/dev/null || fail 'Git is required.'
[[ $(git rev-parse --show-toplevel 2>/dev/null) == "$base" ]] || fail 'Run from a Git checkout rooted at the release helper.'
[[ $(git symbolic-ref --quiet --short HEAD) == main ]] || fail 'Current branch must be main (not detached HEAD).'
check_clean() {
	local status
	status=$(git status --porcelain --untracked-files=all) || fail 'Cannot inspect worktree.'
	[[ -z $status ]] || fail 'Git worktree must be clean, including untracked files.'
}
check_clean
[[ -f bin/codex-sync && ! -L bin/codex-sync ]] || fail 'Canonical VERSION file must be a regular non-symlink file.'
git ls-files --error-unmatch -- bin/codex-sync >/dev/null || fail 'Canonical VERSION file must be tracked.'
numeric='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
mapfile -t definitions < <(grep -E '(^|[^[:alnum:]_])VERSION[[:space:]]*=' bin/codex-sync)
[[ ${#definitions[@]} == 1 && ${definitions[0]} =~ ^readonly\ VERSION=(${numeric})$ ]] || fail 'Expected exactly one literal numeric readonly VERSION constant.'
current=${BASH_REMATCH[1]}
if [[ -z $level ]]; then
	printf 'Current version: %s\nChoose bump (major/minor/patch): ' "$current" >&2
	read -r level || fail 'No bump selected.'
fi
# Increment decimal text without machine-integer overflow.
increment() {
	local value=$1 suffix=''
	while [[ $value == *9 ]]; do
		suffix=0$suffix
		value=${value%9}
	done
	if [[ -z $value ]]; then
		REPLY=1$suffix
	else REPLY=${value%?}$((${value: -1} + 1))$suffix; fi
}
IFS=. read -r major minor patch <<<"$current"
case $level in
major)
	increment "$major"
	target=$REPLY.0.0
	;;
minor)
	increment "$minor"
	target=$major.$REPLY.0
	;;
patch)
	increment "$patch"
	target=$major.$minor.$REPLY
	;;
*) fail 'Choose major, minor, or patch.' ;;
esac
remote=$(git remote get-url --push --all origin) || fail 'origin must have a valid push URL.'
[[ -n $remote && $remote != *$'\n'* ]] || fail 'origin must have exactly one push URL.'
check_tag() {
	local refs tags
	tags=$(git tag --list "$target") || fail 'Cannot inspect local tags.'
	[[ -z $tags ]] || fail "Tag $target already exists locally."
	refs=$(git ls-remote -- "$remote" refs/heads/main "refs/tags/$target" "refs/tags/$target^{}") || fail 'Cannot inspect origin push destination.'
	[[ $refs != *$'\t'"refs/tags/$target"* ]] || fail "Tag $target already exists on origin."
	[[ $refs == *$'\trefs/heads/main'* ]] || fail 'origin must contain main.'
}
[[ $(git config --bool --get remote.origin.mirror || true) != true ]] || fail 'origin must not be a mirror remote.'
check_tag
head=$(git rev-parse HEAD) || fail 'Cannot resolve HEAD.'
printf 'Current version: %s\nBump: %s\nNew version: %s\nRemote: %s\n' "$current" "$level" "$target" "$remote"
printf 'Commit, tag %s, and push main and tag to origin? [y/N] ' "$target" >&2
answer=''
read -r answer || true
case $answer in y | Y | yes | YES | Yes) ;; *)
	printf 'Release cancelled.\n'
	exit 0
	;;
esac
check_clean
[[ $(git symbolic-ref --quiet --short HEAD) == main && $(git rev-parse HEAD) == "$head" ]] || fail 'Branch or HEAD changed during confirmation.'
check_tag
sed -i "s/^readonly VERSION=$current$/readonly VERSION=$target/" bin/codex-sync || fail 'Could not update VERSION.'
git add -- bin/codex-sync || fail 'Could not stage VERSION; inspect local changes.'
git commit -m "build: bump version" || fail 'Commit failed; inspect staged VERSION before retrying.'
git -c tag.gpgSign=false tag -a "$target" -m "$target" || fail 'Tag creation failed; version commit remains local.'
git -c push.followTags=false push --atomic origin refs/heads/main:refs/heads/main "refs/tags/$target:refs/tags/$target" || fail 'Atomic push failed; local commit and tag remain. Inspect origin before retrying; no force push was attempted.'
printf 'Released %s.\n' "$target"

#!/usr/bin/env bash
set -euo pipefail
base=$(cd -- "$(dirname -- "$0")" && pwd -P)
force=false
case ${1:-} in
--force)
	force=true
	shift
	;;
--help)
	printf 'Usage: install.sh [--force]\n'
	exit 0
	;;
esac
[[ $# == 0 ]] || {
	printf 'Usage: install.sh [--force]\n' >&2
	exit 2
}
# Prepare the prospective bytes before comparing or approving destinations.
prepared=$(mktemp -d)
trap 'rm -rf -- "$prepared"' EXIT
if [[ -f $base/scripts/build-metadata.sh ]]; then
	bash "$base/scripts/build-metadata.sh" "$prepared/codex-sync"
else
	cp -- "$base/bin/codex-sync" "$prepared/codex-sync"
fi
for name in cpush cpull; do cp -- "$base/bin/$name" "$prepared/$name"; done
target=$HOME/.local/bin
names=(codex-sync cpush cpull)
updates=()
collisions=()
changes=()
permissions=()
managed_script() {
	local header marker
	{
		IFS= read -r header && IFS= read -r marker
	} <"$1" || return 1
	[[ $header == '#!/usr/bin/env bash' && $marker == '# codex-sync' ]]
}
for name in "${names[@]}"; do
	path=$target/$name
	if [[ ! -L $path && -e $path && ! -f $path ]]; then
		printf '❌ Cannot replace non-regular file or directory: %s\n' "$path" >&2
		exit 1
	fi
	if [[ -f $path && ! -L $path ]] && cmp -s -- "$prepared/$name" "$path"; then
		# Restore executable permissions if necessary without rewriting the file.
		if [[ ! -x $path ]]; then permissions+=("$path"); fi
		continue
	fi
	changes+=("$name")
	if [[ -e $path || -L $path ]]; then
		if [[ -f $path && ! -L $path ]] && managed_script "$path"; then
			updates+=("$path")
		else
			collisions+=("$path")
		fi
	fi
done
confirm() {
	local prompt=$1 answer=''
	$force && return 0
	[[ -t 0 && -t 2 ]] || {
		printf '❌ Noninteractive collision: updates/replacements require --force.\n' >&2
		return 1
	}
	printf '⚠️ %s [y/N] ' "$prompt" >&2
	IFS= read -r answer || return 1
	case $answer in
	y | Y | yes | YES | Yes) return 0 ;;
	*) return 1 ;;
	esac
}
# Report and approve the entire set before creating or replacing any target.
# Read only literal stamps, never source or execute an installed command.
# VERSION alone describes release intent, not verified build provenance.
stamped_version() {
	local path=$1 line stamp='' count=0
	if [[ ! -L $path && -f $path && -r $path ]] && managed_script "$path"; then
		while IFS= read -r line || [[ -n $line ]]; do
			if [[ $line == 'readonly BUILD_METADATA='* ]]; then
				count=$((count + 1))
				stamp=${line#readonly BUILD_METADATA=}
			fi
		done <"$path"
		if [[ $count == 1 && $stamp =~ ^\'([0-9]+\.[0-9]+\.[0-9]+(-[0-9]+-g[0-9a-f]+(-dirty)?)?|\?\.\?\.\?(-g[0-9a-f]+(-dirty)?)?)\'$ ]]; then
			printf '%s' "${BASH_REMATCH[1]}"
			return
		fi
	fi
	printf '?.?.?'
}
existing=false
for name in "${names[@]}"; do
	if [[ -e $target/$name || -L $target/$name ]]; then existing=true; fi
done
if $existing; then
	installed_version=$(stamped_version "$target/codex-sync")
	incoming_version=$(stamped_version "$prepared/codex-sync")
	printf 'ℹ️ codex-sync (%s → %s)\n' "$installed_version" "$incoming_version" >&2
	for name in "${names[@]}"; do
		path=$target/$name
		if [[ ! -e $path && ! -L $path ]]; then
			state='new'
		elif [[ ! -L $path && -f $path ]] && cmp -s -- "$prepared/$name" "$path"; then
			state='identical'
		else
			state='different; replace'
		fi
		color='' reset=''
		if [[ -t 2 && ! ${NO_COLOR+x} ]]; then
			case $state in
			'identical') color=$'\033[32m' ;;
			'different; replace') color=$'\033[33m' ;;
			esac
		fi
		if [[ -n $color ]]; then reset=$'\033[0m'; fi
		# Style only the status word, keeping names and explanatory text plain.
		printf '  %s: %s%s%s%s\n' "$name" "$color" "${state%%[; ]*}" "$reset" "${state#"${state%%[; ]*}"}" >&2
	done
fi
if ((${#collisions[@]})); then
	printf '⚠️ Existing command collisions (unrelated files or symlinks):\n' >&2
	printf '  %s\n' "${collisions[@]}" >&2
fi
if ((${#updates[@]})); then confirm 'Update these codex-sync scripts?' || exit 1; fi
if ((${#collisions[@]})); then confirm 'Replace these unrelated files or symlinks?' || exit 1; fi
if ((${#changes[@]} == 0)); then
	for path in "${permissions[@]}"; do chmod 755 -- "$path"; done
	if ((${#permissions[@]})); then
		printf '✅ Restored executable permissions in %s\n' "$target"
	else
		printf '✅ No changes in %s\n' "$target"
	fi
	exit 0
fi
mkdir -p -- "$target"
stage=$(mktemp -d "$target/.codex-sync.XXXXXXXX")
trap 'rm -rf -- "$stage" "$prepared"' EXIT
for name in "${changes[@]}"; do install -m 755 -- "$prepared/$name" "$stage/$name"; done
for path in "${permissions[@]}"; do chmod 755 -- "$path"; done
for name in "${changes[@]}"; do mv -fT -- "$stage/$name" "$target/$name"; done
printf '✅ Installed commands in %s\n' "$target"

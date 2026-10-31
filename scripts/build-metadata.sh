#!/usr/bin/env bash
set -euo pipefail
# Output a validated display version; optionally stamp a separate copy of bin/codex-sync.
base=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
[[ $# == 0 || $# == 1 ]] || exit 2
mapfile -t versions < <(sed -n 's/^readonly VERSION=//p' "$base/bin/codex-sync")
[[ ${#versions[@]} == 1 && ${versions[0]} =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || exit 1
version=${versions[0]}
display='?.?.?'
# Do not borrow an enclosing project's repository for an extracted source tree.
if command -v git >/dev/null 2>&1 && [[ $(git -C "$base" rev-parse --show-toplevel 2>/dev/null) == "$base" ]]; then
	description=$(git -C "$base" describe --tags --always --long --dirty --match '[0-9]*.[0-9]*.[0-9]*' 2>/dev/null) || description=''
	if [[ $description =~ ^([0-9]+\.[0-9]+\.[0-9]+)-([0-9]+)-g([0-9a-f]+)(-dirty)?$ ]]; then
		if [[ ${BASH_REMATCH[1]} == "$version" && ${BASH_REMATCH[2]} == 0 && -z ${BASH_REMATCH[4]} ]]; then
			display=$version
		else
			display=$description
		fi
	elif [[ $description =~ ^[0-9a-f]+(-dirty)?$ ]]; then
		display="?.?.?-g$description"
	fi
fi
if [[ $# == 0 ]]; then
	printf '%s' "$display"
else
	# Preserve a package stamp; unstamped sources receive the verified display version.
	[[ $1 != "$base/bin/codex-sync" && ! $1 -ef $base/bin/codex-sync ]] || exit 1
	if grep -qx "readonly BUILD_METADATA=''" "$base/bin/codex-sync"; then
		sed "s/^readonly BUILD_METADATA=''/readonly BUILD_METADATA='$display'/" "$base/bin/codex-sync" >"$1"
	else
		cat -- "$base/bin/codex-sync" >"$1"
	fi
fi

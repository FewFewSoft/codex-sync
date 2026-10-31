#!/usr/bin/env bash
set -euo pipefail
base=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
[[ $# == 1 ]] || {
	echo 'Usage: release-version.sh TAG' >&2
	exit 2
}
numeric_version='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
[[ $1 =~ ^${numeric_version}$ ]] || {
	echo 'Release tags must be exactly X.Y.Z (no v prefix or leading zeros).' >&2
	exit 1
}
# Read the constant as data, never source or evaluate application code.
mapfile -t definitions < <(grep -E '(^|[^[:alnum:]_])VERSION[[:space:]]*=' "$base/bin/codex-sync")
[[ ${#definitions[@]} == 1 ]] || {
	echo 'Expected exactly one unambiguous VERSION definition.' >&2
	exit 1
}
[[ ${definitions[0]} =~ ^readonly\ VERSION=(${numeric_version})$ ]] || {
	echo 'Expected a literal numeric readonly VERSION constant.' >&2
	exit 1
}
[[ ${BASH_REMATCH[1]} == "$1" ]] || {
	echo 'Release tag does not match bin/codex-sync VERSION.' >&2
	exit 1
}

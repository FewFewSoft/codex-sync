#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=tests/helpers.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/helpers.sh"
run --version
version=$(cat "$tmp/out")
run --help
[[ $(head -n 1 "$tmp/out") == "$version — synchronize projects over SSH" ]]
[[ $(wc -l <"$tmp/out") -le 40 ]]
for section in 'Usage:' 'Commands:' 'Options (push/pull):' 'General options:' 'Examples:'; do
	grep -F -- "$section" "$tmp/out" >/dev/null
done
if grep -Ei 'physical|worktree|mkdir|no-global-ignore|metadata|nearest|missing marker|missing remote' "$tmp/out"; then
	exit 1
fi
cp "$tmp/out" "$tmp/help"
for command in push pull inspect; do
	run "$command" --help
	cmp "$tmp/help" "$tmp/out"
	run "$command" --version
	[[ $(cat "$tmp/out") == "$version" ]]
done
[[ ! -e $LOG.ssh && ! -e $LOG.rsync ]]
ok 'concise versioned help and version output require no transfer tools'

#!/usr/bin/env bash
set -euo pipefail
[[ $# == 2 || $# == 3 ]] || {
	echo 'Usage: build-installer.sh MAKESELF_DIRECTORY OUTPUT_DIRECTORY [RELEASE_TAG]' >&2
	exit 2
}
base=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
makeself=$(cd -- "$1" && pwd -P)
mkdir -p -- "$2"
out=$(cd -- "$2" && pwd -P)
if [[ $# == 3 ]]; then
	bash "$base/scripts/release-version.sh" "$3"
fi
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/payload/bin" "$work/home" "$work/config" "$work/tmp"
# Explicit allowlist: never package the working tree or CI tooling.
install -m 755 "$base/install.sh" "$base/uninstall.sh" "$work/payload/"
install -m 755 "$base/bin/codex-sync" "$base/bin/cpush" "$base/bin/cpull" "$work/payload/bin/"
bash "$base/scripts/build-metadata.sh" "$work/payload/bin/codex-sync"
display=$(bash "$base/scripts/build-metadata.sh")
[[ $(bash "$work/payload/bin/codex-sync" --version) == "codex-sync $display" ]]
if [[ $# == 3 ]]; then
	[[ $display == "$3" ]] || {
		echo 'Release requires clean exact-tag metadata matching VERSION.' >&2
		exit 1
	}
fi
archive="$out/codex-sync-${3:-snapshot}.run"
bash "$makeself/makeself.sh" --header "$makeself/makeself-header.sh" \
	--gzip "$work/payload" "$archive" "codex-sync $display" ./install.sh
chmod 755 "$archive"
export HOME="$work/home" XDG_CONFIG_HOME="$work/config" TMPDIR="$work/tmp"
bash "$archive" --check
bash "$archive" --noexec --target "$work/extracted"
diff -r "$work/payload" "$work/extracted"
bash "$archive" --nox11
for name in codex-sync cpush cpull; do
	cmp "$work/payload/bin/$name" "$HOME/.local/bin/$name"
	test -x "$HOME/.local/bin/$name"
	[[ $("$HOME/.local/bin/$name" --version) == "codex-sync $display" ]]
done
bash "$work/extracted/uninstall.sh"
for name in codex-sync cpush cpull; do
	test ! -e "$HOME/.local/bin/$name"
done

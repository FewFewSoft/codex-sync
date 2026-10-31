#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=tests/helpers.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/helpers.sh"
source_tree=$tmp/source
mkdir -p "$source_tree/bin" "$source_tree/scripts" "$tmp/makeself"
cp "$repo/bin/"* "$source_tree/bin/"
cp "$repo/scripts/"*.sh "$source_tree/scripts/"
cp "$repo/install.sh" "$repo/uninstall.sh" "$source_tree/"
version=$(canonical_version "$source_tree/bin/codex-sync")
bash "$source_tree/scripts/release-version.sh" "$version"
for tag in v1.2.0 01.2.0 1.02.0 1.2.00 1.2.0-rc1 1.2 '1.2.0;exit' "1$version"; do
	if bash "$source_tree/scripts/release-version.sh" "$tag" >"$tmp/out" 2>&1; then exit 1; fi
done
printf '\nreadonly VERSION=%s\n' "$version" >>"$source_tree/bin/codex-sync"
if bash "$source_tree/scripts/release-version.sh" "$version" >"$tmp/out" 2>&1; then exit 1; fi
cp "$repo/bin/codex-sync" "$source_tree/bin/codex-sync"
sed "s/^readonly VERSION=.*/readonly VERSION=\$(touch SHOULD_NOT_EXIST)/" "$repo/bin/codex-sync" >"$source_tree/bin/codex-sync"
(
	cd "$tmp"
	if bash "$source_tree/scripts/release-version.sh" "$version" >"$tmp/out" 2>&1; then exit 1; fi
	[[ ! -e SHOULD_NOT_EXIST ]]
)
cp "$repo/bin/codex-sync" "$source_tree/bin/codex-sync"
ok 'strict tag grammar, canonical version match, duplicate rejection and no evaluation'
cat >"$tmp/mock/git" <<'MOCK'
#!/usr/bin/env bash
case $3 in
rev-parse) printf '%s\n' "$2" ;;
describe) printf '%s\n' "$MOCK_DESCRIBE" ;;
esac
MOCK
chmod +x "$tmp/mock/git"
export MOCK_DESCRIBE=$version-1-gabc123
if bash "$source_tree/scripts/build-installer.sh" "$tmp/makeself" "$tmp/dist" "$version" >"$tmp/out" 2>&1; then exit 1; fi
grep -q 'clean exact-tag metadata' "$tmp/out"
[[ ! -e $HOME/.local/bin/codex-sync ]]
ok 'release rejects non-exact metadata before packaging or installation'
if [[ -n ${MAKESELF_DIR:-} ]]; then
	for description in "$version-0-gabc123" "$version-2-gabc123-dirty"; do
		MOCK_DESCRIBE=$description
		args=()
		[[ $description != "$version-0-gabc123" ]] || args+=("$version")
		bash "$source_tree/scripts/build-installer.sh" "$MAKESELF_DIR" "$tmp/dist" "${args[@]}" >"$tmp/out" 2>&1
		archive="$tmp/dist/codex-sync-${args[0]:-snapshot}.run"
		[[ -x $archive ]]
		bash "$archive" --noexec --target "$tmp/inspect" >"$tmp/out" 2>&1
		expected=$description
		[[ ${#args[@]} == 0 ]] || expected=$version
		[[ $(bash "$tmp/inspect/bin/codex-sync" --version) == "codex-sync $expected" ]]
		[[ $(find "$tmp/inspect" -type f | wc -l) == 5 ]]
		[[ ! -e $HOME/.local/bin/codex-sync ]]
		grep -qx "readonly BUILD_METADATA=''" "$source_tree/bin/codex-sync"
		rm -rf -- "$tmp/inspect"
	done
	ok 'real Makeself release/snapshot archives, allowlist, stamps and isolated install/uninstall'
else
	printf 'skip - archive integration requires MAKESELF_DIR (Makeself 2.5.0)\n'
fi

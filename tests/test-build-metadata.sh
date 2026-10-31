#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=tests/helpers.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/helpers.sh"
source_tree=$tmp/source
mkdir -p "$source_tree/bin" "$source_tree/scripts" "$source_tree/.git"
cp "$repo/bin/"* "$source_tree/bin/"
cp "$repo/scripts/build-metadata.sh" "$source_tree/scripts/"
cp "$repo/install.sh" "$source_tree/"
version=$(canonical_version "$source_tree/bin/codex-sync")
cat >"$tmp/mock/git" <<'MOCK'
#!/usr/bin/env bash
case $3 in
rev-parse) printf '%s\n' "${MOCK_ROOT:-$2}" ;;
describe) [[ ${MOCK_FAIL:-0} == 0 ]] || exit 1; printf '%s\n' "$MOCK_DESCRIBE" ;;
esac
MOCK
chmod +x "$tmp/mock/git"
export MOCK_DESCRIBE
for description in "$version-0-gabc123" "$version-3-gabc123" "$version-0-gabc123-dirty" abc123 abc123-dirty 1.2.0-0-gabc123 1.1.0-4-gabc123; do
	MOCK_DESCRIBE=$description
	expected=$description
	[[ ! $description =~ ^[0-9a-f]+(-dirty)?$ ]] || expected="?.?.?-g$description"
	[[ $description != "$version-0-gabc123" ]] || expected=$version
	[[ $("$source_tree/bin/codex-sync" --version) == "codex-sync $expected" ]]
	[[ $("$source_tree/bin/codex-sync" --help | head -n 1) == "codex-sync $expected — synchronize projects over SSH" ]]
	"$source_tree/install.sh" --force >"$tmp/out" 2>"$tmp/err"
	[[ $("$HOME/.local/bin/codex-sync" --version) == "codex-sync $expected" ]]
	identity=$(stat -c '%i:%Y' "$HOME/.local/bin/codex-sync")
	"$source_tree/install.sh" >"$tmp/out"
	[[ $(stat -c '%i:%Y' "$HOME/.local/bin/codex-sync") == "$identity" ]]
done
ok 'describe tags, distance, hashes, dirty state, help, stamping and identical reinstall'
MOCK_DESCRIBE=$version-3-gabc123
bash "$source_tree/scripts/build-metadata.sh" "$tmp/stamp-one"
bash "$source_tree/scripts/build-metadata.sh" "$tmp/stamp-two"
cmp "$tmp/stamp-one" "$tmp/stamp-two"
ln -s "$source_tree/bin/codex-sync" "$tmp/source-link"
if bash "$source_tree/scripts/build-metadata.sh" "$tmp/source-link"; then exit 1; fi
grep -qx "readonly BUILD_METADATA=''" "$source_tree/bin/codex-sync"
(
	cd "$tmp/work/demo"
	[[ $("$source_tree/bin/codex-sync" --version) == "codex-sync $version-3-gabc123" ]]
)
ok 'deterministic copies, source symlink protection and cwd-independent revision'

for description in 'bad tag' '1.2.0;touch x' ''; do
	MOCK_DESCRIBE=$description
	[[ $("$source_tree/bin/codex-sync" --version) == 'codex-sync ?.?.?' ]]
done
MOCK_DESCRIBE=$version-3-gabc123
export MOCK_FAIL=1
[[ $("$source_tree/bin/codex-sync" --version) == 'codex-sync ?.?.?' ]]
unset MOCK_FAIL
export MOCK_ROOT=$tmp
[[ $("$source_tree/bin/codex-sync" --version) == 'codex-sync ?.?.?' ]]
unset MOCK_ROOT
MOCK_DESCRIBE=$version-0-gabc123
bash "$source_tree/scripts/build-metadata.sh" "$tmp/release-stamp"
[[ $(bash "$tmp/release-stamp" --version) == "codex-sync $version" ]]
printf '#!/usr/bin/env bash\nexit 127\n' >"$tmp/mock/git"
[[ $("$source_tree/bin/codex-sync" --version) == 'codex-sync ?.?.?' ]]
ok 'invalid output, Git failure/unavailability and enclosing repositories fall back safely'
# Package a stamped script without Git or build tooling; installation retains it.
cp "$HOME/.local/bin/codex-sync" "$source_tree/bin/codex-sync"
rm -rf "$source_tree/.git" "$source_tree/scripts"
"$source_tree/install.sh" --force >"$tmp/out"
[[ $("$HOME/.local/bin/codex-sync" --version) == 'codex-sync 1.1.0-4-gabc123' ]]
grep -qx "readonly VERSION=$version" "$source_tree/bin/codex-sync"
ok 'packaged stamp survives installation without Git and canonical version stays unchanged'
# An extracted unstamped source must not claim VERSION without provenance.
sed "s/^readonly BUILD_METADATA=.*/readonly BUILD_METADATA=''/" "$source_tree/bin/codex-sync" >"$tmp/unstamped"
cp "$tmp/unstamped" "$source_tree/bin/codex-sync"
[[ $("$source_tree/bin/codex-sync" --version) == 'codex-sync ?.?.?' ]]
"$source_tree/install.sh" --force >"$tmp/out" 2>"$tmp/err"
[[ $("$HOME/.local/bin/codex-sync" --version) == 'codex-sync ?.?.?' ]]
ok 'extracted source and its installation without provenance stay unknown'

cp "$tmp/release-stamp" "$source_tree/bin/codex-sync"
"$source_tree/install.sh" --force >"$tmp/out"
[[ $("$HOME/.local/bin/codex-sync" --version) == "codex-sync $version" ]]
[[ $("$HOME/.local/bin/codex-sync" --help | head -n 1) == "codex-sync $version — synchronize projects over SSH" ]]
ok 'official tagged package retains exact version without checkout provenance'

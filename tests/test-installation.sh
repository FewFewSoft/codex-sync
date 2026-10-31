#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=tests/helpers.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/helpers.sh"
bash "$repo/scripts/build-metadata.sh" "$tmp/expected-codex-sync"
printf 'global-cache/\n' >"$XDG_CONFIG_HOME/codex-sync/ignore"
mkdir -p "$HOME/projects/demo"
printf 'local-cache/\n' >"$HOME/projects/demo/.codexignore"
"$repo/install.sh" >"$tmp/out" 2>"$tmp/err"
[[ ! -s $tmp/err ]]
[[ $(cat "$tmp/out") == "✅ Installed commands in $HOME/.local/bin" ]]
for name in codex-sync cpush cpull; do
	expected=$repo/bin/$name
	[[ $name != codex-sync ]] || expected=$tmp/expected-codex-sync
	cmp "$expected" "$HOME/.local/bin/$name"
	[[ -x $HOME/.local/bin/$name && ! -L $HOME/.local/bin/$name ]]
done
# An unchanged install must not stage or invoke install/mv, even with --force.
for command in install mv mkdir; do
	printf '#!/usr/bin/env bash\nexit 97\n' >"$tmp/mock/$command"
	chmod +x "$tmp/mock/$command"
done
identities=()
for name in codex-sync cpush cpull; do
	identities+=("$(stat -c '%i:%Y:%a' "$HOME/.local/bin/$name")")
done
"$repo/install.sh" --force </dev/null >"$tmp/out" 2>"$tmp/err"
[[ $(cat "$tmp/out") == "✅ No changes in $HOME/.local/bin" ]]
[[ $(wc -l <"$tmp/err") == 4 ]]
for name in codex-sync cpush cpull; do grep -Fxq "  $name: identical" "$tmp/err"; done
for i in "${!identities[@]}"; do
	names=(codex-sync cpush cpull)
	[[ $(stat -c '%i:%Y:%a' "$HOME/.local/bin/${names[$i]}") == "${identities[$i]}" ]]
done
for command in install mv mkdir; do rm "$tmp/mock/$command"; done
identity=$(stat -c '%i:%Y:%a' "$HOME/.local/bin/codex-sync")
"$repo/install.sh" </dev/null >"$tmp/out"
[[ $(stat -c '%i:%Y:%a' "$HOME/.local/bin/codex-sync") == "$identity" ]]
for name in codex-sync cpush cpull; do
	[[ $(sed -n '2p' "$repo/bin/$name") == '# codex-sync' ]]
done
[[ $("$HOME/.local/bin/codex-sync" --version) == "$("$repo/bin/codex-sync" --version)" ]]
chmod 644 "$HOME/.local/bin/cpush"
permission_inode=$(stat -c %i "$HOME/.local/bin/cpush")
"$repo/install.sh" </dev/null >"$tmp/out"
[[ -x $HOME/.local/bin/cpush && $(stat -c %i "$HOME/.local/bin/cpush") == "$permission_inode" ]]
printf 'modified\n' >"$HOME/.local/bin/cpush"
printf 'unrelated\n' >"$HOME/.local/bin/cpull"
if "$repo/install.sh" </dev/null >"$tmp/out" 2>"$tmp/err"; then exit 1; fi
grep -q '^⚠️ Existing command collisions' "$tmp/err"
grep -q '^❌ Noninteractive collision:' "$tmp/err"
grep -q '/cpush' "$tmp/err"
grep -q '/cpull' "$tmp/err"
[[ $(cat "$HOME/.local/bin/cpush") == modified ]]
ok 'copy install, identical reinstall, all collisions reported and refused'
"$repo/install.sh" --force >"$tmp/out" 2>"$tmp/err"
printf 'modified\n' >>"$HOME/.local/bin/cpush"
"$repo/uninstall.sh" >"$tmp/out" 2>"$tmp/err"
[[ ! -e $HOME/.local/bin/cpush && ! -e $HOME/.local/bin/codex-sync && ! -e $HOME/.local/bin/cpull ]]
[[ -f $XDG_CONFIG_HOME/codex-sync/ignore && -f $HOME/projects/demo/.codexignore ]]
"$repo/install.sh" --force >"$tmp/out" 2>"$tmp/err"
"$repo/uninstall.sh" >"$tmp/out"
grep -q "^✅ Removed $HOME/.local/bin/" "$tmp/out"
[[ ! -e $HOME/.local/bin/cpush ]]
ok 'forced replacement and managed uninstall removes modified commands and preserves config'

# All fixtures live under the isolated HOME provided by helpers.sh.
export INSTALL_COMMAND=$repo/install.sh
cat >"$tmp/mock/install-runner" <<'RUNNER'
#!/usr/bin/env bash
exec "$INSTALL_COMMAND"
RUNNER
chmod +x "$tmp/mock/install-runner"
reset_install() {
	rm -rf -- "$HOME/.local/bin"
	"$repo/install.sh" >"$tmp/out"
}
managed_update() { printf '# old implementation\n' >>"$HOME/.local/bin/cpush"; }
reset_install
managed_update
rm "$HOME/.local/bin/cpull"
if "$repo/install.sh" <<<y >"$tmp/out" 2>"$tmp/err"; then exit 1; fi
[[ $(wc -l <"$tmp/err") == 5 ]]
grep -Eq '^ℹ️ codex-sync \(.+ → .+\)$' "$tmp/err"
grep -Fxq '  codex-sync: identical' "$tmp/err"
grep -Fxq '  cpush: different; replace' "$tmp/err"
grep -Fxq '  cpull: new' "$tmp/err"
grep -Fxq '❌ Noninteractive collision: updates/replacements require --force.' "$tmp/err"
[[ ! -e $HOME/.local/bin/cpull ]]
grep -Fq '# old implementation' "$HOME/.local/bin/cpush"
ok 'noninteractive managed update refuses even affirmative input before installing absent commands'
# Near-match and misplaced markers cannot classify an unrelated command as managed.
for header in $'#!/usr/bin/env bash\n# codex-sync extra' $'#!/bin/bash\n# codex-sync' $'#!/usr/bin/env bash\n\n# codex-sync'; do
	printf '%s\n' "$header" >"$HOME/.local/bin/cpush"
	if "$repo/install.sh" </dev/null >"$tmp/out" 2>"$tmp/err"; then exit 1; fi
	grep -Fq 'Existing command collisions' "$tmp/err"
	if grep -Fq 'Existing codex-sync updates:' "$tmp/err"; then exit 1; fi
done
ok 'only the exact expected two-line header identifies managed scripts'
for referent in "$tmp/referent" "$tmp/missing" "$tmp/directory"; do
	reset_install
	printf 'preserve\n' >"$tmp/referent"
	mkdir -p "$tmp/directory"
	rm "$HOME/.local/bin/cpush"
	ln -s "$referent" "$HOME/.local/bin/cpush"
	if "$repo/install.sh" </dev/null >"$tmp/out" 2>"$tmp/err"; then exit 1; fi
	[[ -L $HOME/.local/bin/cpush ]]
	"$repo/install.sh" --force >"$tmp/out" 2>"$tmp/err"
	[[ ! -L $HOME/.local/bin/cpush && -x $HOME/.local/bin/cpush ]]
	[[ $(cat "$tmp/referent") == preserve && ! -e $tmp/missing && -d $tmp/directory ]]
done
reset_install
rm "$HOME/.local/bin/cpull"
mkdir "$HOME/.local/bin/cpull"
if "$repo/install.sh" --force >"$tmp/out" 2>"$tmp/err"; then exit 1; fi
[[ -d $HOME/.local/bin/cpull ]]
ok 'symlinks require explicit replacement and preserve referents; directories refuse force'
# A failed stage must leave every destination untouched.
reset_install
managed_update
rm "$HOME/.local/bin/cpull"
cat >"$tmp/mock/install" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
chmod +x "$tmp/mock/install"
if "$repo/install.sh" --force >"$tmp/out" 2>"$tmp/err"; then exit 1; fi
[[ ! -e $HOME/.local/bin/cpull ]]
grep -Fq '# old implementation' "$HOME/.local/bin/cpush"
[[ -z $(find "$HOME/.local/bin" -maxdepth 1 -name '.codex-sync.*' -print) ]]
rm "$tmp/mock/install"
ok 'stage failure preserves destinations and cleans staging directory'
# A packaged incoming stamp and installed metadata are read as data only.
package=$tmp/package
mkdir -p "$package/bin"
cp "$repo/install.sh" "$package/"
cp "$repo/bin/"{codex-sync,cpush,cpull} "$package/bin/"
sed "s/^readonly BUILD_METADATA=.*/readonly BUILD_METADATA='2.0.0-3-gabc123-dirty'/" "$repo/bin/codex-sync" >"$package/bin/codex-sync"
rm -rf -- "$HOME/.local/bin"
"$package/install.sh" >"$tmp/out" 2>"$tmp/err"
"$package/install.sh" </dev/null >"$tmp/out" 2>"$tmp/err"
grep -Fxq 'ℹ️ codex-sync (2.0.0-3-gabc123-dirty → 2.0.0-3-gabc123-dirty)' "$tmp/err"
for name in codex-sync cpush cpull; do grep -Fq "$name: identical" "$tmp/err"; done
# Installed payload must stay literal and must never run.
# shellcheck disable=SC2016
printf '\ntouch "$HOME/executed"\n' >>"$HOME/.local/bin/codex-sync"
if "$package/install.sh" </dev/null >"$tmp/out" 2>"$tmp/err"; then exit 1; fi
grep -Fxq 'ℹ️ codex-sync (2.0.0-3-gabc123-dirty → 2.0.0-3-gabc123-dirty)' "$tmp/err"
grep -Fq 'codex-sync: different; replace' "$tmp/err"
[[ ! -e $HOME/executed ]]
sed -i "s/^readonly BUILD_METADATA=.*/readonly BUILD_METADATA='1.0.0'/" "$HOME/.local/bin/codex-sync"
if "$package/install.sh" </dev/null >"$tmp/out" 2>"$tmp/err"; then exit 1; fi
grep -Fxq 'ℹ️ codex-sync (1.0.0 → 2.0.0-3-gabc123-dirty)' "$tmp/err"
for metadata in "''" "'bad'" "'\$(touch \"$HOME/executed\")'"; do
	head -n 2 "$repo/bin/codex-sync" >"$HOME/.local/bin/codex-sync"
	printf 'readonly VERSION=99.0.0\nreadonly BUILD_METADATA=%s\n' "$metadata" >>"$HOME/.local/bin/codex-sync"
	if "$package/install.sh" </dev/null >"$tmp/out" 2>"$tmp/err"; then exit 1; fi
	grep -Fxq 'ℹ️ codex-sync (?.?.? → 2.0.0-3-gabc123-dirty)' "$tmp/err"
	[[ ! -e $HOME/executed ]]
done
printf "readonly BUILD_METADATA='1.0.0'\n" >>"$HOME/.local/bin/codex-sync"
if "$package/install.sh" </dev/null >"$tmp/out" 2>"$tmp/err"; then exit 1; fi
grep -Fxq 'ℹ️ codex-sync (?.?.? → 2.0.0-3-gabc123-dirty)' "$tmp/err"
rm "$HOME/.local/bin/codex-sync"
ln -s "$package/bin/codex-sync" "$HOME/.local/bin/codex-sync"
if "$package/install.sh" </dev/null >"$tmp/out" 2>"$tmp/err"; then exit 1; fi
grep -Fxq 'ℹ️ codex-sync (?.?.? → 2.0.0-3-gabc123-dirty)' "$tmp/err"
"$package/install.sh" --force >"$tmp/out" 2>"$tmp/err"
[[ ! -L $HOME/.local/bin/codex-sync && ! -e $HOME/executed ]]
ok 'version summaries distinguish identical and differing builds without executing installed code or trusting VERSION, malformed stamps or links'
if ! command -v script >/dev/null; then
	printf 'skip - interactive installer tests require util-linux script\n'
	exit 0
fi
terminal_install() {
	printf '%s' "$1" | script -q -e -c install-runner /dev/null >"$tmp/terminal"
}
for answer in $'\n' $'n\n' $'garbage\n' $'\004'; do
	reset_install
	managed_update
	rm "$HOME/.local/bin/cpull"
	if terminal_install "$answer"; then exit 1; fi
	grep -Fq 'Update these codex-sync scripts? [y/N]' "$tmp/terminal"
	if grep -Fq 'Existing codex-sync updates:' "$tmp/terminal"; then exit 1; fi
	if grep -Fq "  $HOME/.local/bin/" "$tmp/terminal"; then exit 1; fi
	[[ ! -e $HOME/.local/bin/cpull ]]
	grep -Fq '# old implementation' "$HOME/.local/bin/cpush"
done
for answer in y Y yes YES Yes; do
	reset_install
	managed_update
	identity=$(stat -c '%i:%Y:%a' "$HOME/.local/bin/codex-sync")
	rm "$HOME/.local/bin/cpull"
	terminal_install "$answer"$'\n'
	cmp "$repo/bin/cpush" "$HOME/.local/bin/cpush"
	[[ -x $HOME/.local/bin/cpull ]]
	[[ $(stat -c '%i:%Y:%a' "$HOME/.local/bin/codex-sync") == "$identity" ]]
done
ok 'managed updates default to No and accepted answers update mixed absent/unchanged/managed sets'
reset_install
managed_update
printf 'unrelated\n' >"$HOME/.local/bin/cpull"
if terminal_install $'y\nn\n'; then exit 1; fi
grep -Fq '# old implementation' "$HOME/.local/bin/cpush"
[[ $(cat "$HOME/.local/bin/cpull") == unrelated ]]
grep -Fq 'Replace these unrelated files or symlinks? [y/N]' "$tmp/terminal"
terminal_install $'y\ny\n'
for name in codex-sync cpush cpull; do
	expected=$repo/bin/$name
	[[ $name != codex-sync ]] || expected=$tmp/expected-codex-sync
	cmp "$expected" "$HOME/.local/bin/$name"
	[[ -x $HOME/.local/bin/$name ]]
done
ok 'mixed managed and unrelated sets require separate approvals before any replacement'

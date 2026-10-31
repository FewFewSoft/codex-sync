#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=tests/helpers.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/helpers.sh"
unset NO_COLOR
escape=$'\033'
package=$tmp/package
mkdir -p "$package/bin"
cp "$repo/install.sh" "$package/"
cp "$repo/bin/"{codex-sync,cpush,cpull} "$package/bin/"
sed -i "s/^readonly BUILD_METADATA=.*/readonly BUILD_METADATA='2.0.0'/" "$package/bin/codex-sync"
"$package/install.sh" >"$tmp/out" 2>"$tmp/err"
export COLOR_INSTALL=$package/install.sh COLOR_ERROR=$tmp/err COLOR_OUTPUT=$tmp/out
cat >"$tmp/mock/install-color-runner" <<'RUNNER'
#!/usr/bin/env bash
if [[ ${COLOR_REDIRECT:-} == 1 ]]; then
	exec "$COLOR_INSTALL" --force >"$COLOR_OUTPUT" 2>"$COLOR_ERROR"
fi
exec "$COLOR_INSTALL" --force
RUNNER
chmod +x "$tmp/mock/install-color-runner"
for state in Identical Different Unknown; do
	# Equal metadata may still accompany different bytes.
	cp "$package/bin/codex-sync" "$HOME/.local/bin/codex-sync"
	printf '\n# changed bytes\n' >>"$HOME/.local/bin/codex-sync"
	case $state in
	Identical)
		version=2.0.0
		;;
	Different)
		version=1.0.0
		;;
	Unknown)
		version='?.?.?'
		;;
	esac
	sed -i "s/^readonly BUILD_METADATA=.*/readonly BUILD_METADATA='$version'/" "$HOME/.local/bin/codex-sync"
	cp "$HOME/.local/bin/codex-sync" "$tmp/installed"
	"$package/install.sh" --force >"$tmp/out" 2>"$tmp/err"
	grep -Fxq "ℹ️ codex-sync ($version → 2.0.0)" "$tmp/err"
	grep -Fq 'codex-sync: different; replace' "$tmp/err"
	[[ $(wc -l <"$tmp/err") == 4 ]]
	grep -Fxq '  cpush: identical' "$tmp/err"
	grep -Fxq '  cpull: identical' "$tmp/err"
	[[ $(cat "$tmp/err" "$tmp/out") != *"$escape"* ]]
	cat "$tmp/err" "$tmp/out" >"$tmp/plain"
	if command -v script >/dev/null; then
		cp "$tmp/installed" "$HOME/.local/bin/codex-sync"
		script -q -e -c install-color-runner /dev/null >"$tmp/terminal"
		cp "$tmp/plain" "$tmp/expected"
		sed -i -e "s/: different/: ${escape}[33mdifferent${escape}[0m/" \
			-e "s/: identical/: ${escape}[32midentical${escape}[0m/" "$tmp/expected"
		tr -d '\r' <"$tmp/terminal" >"$tmp/actual"
		cmp "$tmp/expected" "$tmp/actual"
		for value in '' 1; do
			cp "$tmp/installed" "$HOME/.local/bin/codex-sync"
			NO_COLOR=$value script -q -e -c install-color-runner /dev/null >"$tmp/terminal"
			tr -d '\r' <"$tmp/terminal" >"$tmp/actual"
			cmp "$tmp/plain" "$tmp/actual"
		done
		cp "$tmp/installed" "$HOME/.local/bin/codex-sync"
		COLOR_REDIRECT=1 script -q -e -c install-color-runner /dev/null >"$tmp/terminal"
		cat "$tmp/err" "$tmp/out" >"$tmp/actual"
		cmp "$tmp/plain" "$tmp/actual"
		[[ $(cat "$tmp/terminal") != *"$escape"* ]]
	fi
	ok "$state version comparison stays plain without an overall status; each command status has exact terminal/NO_COLOR output"
done
if ! command -v script >/dev/null; then
	printf 'skip - terminal installer color tests require util-linux script\n'
fi

#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=tests/helpers.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/helpers.sh"
export REAL_RSYNC
REAL_RSYNC=$(command -v /usr/bin/rsync)
export REMOTE_DIR=$tmp/remote/demo
mkdir -p "$REMOTE_DIR"
cat >"$tmp/mock/rsync" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$LOG.rsync"
if [[ ${FAIL_PROBE:-0} == 1 ]]; then
 for arg in "$@"; do [[ $arg != --out-format=%i ]] || exit 23; done
fi
if [[ ${FAIL_APPLY:-0} == 1 ]]; then
 dry=false
 for arg in "$@"; do if [[ $arg == --dry-run ]]; then dry=true; fi; done
 $dry || exit 24
fi
args=()
for arg in "$@"; do
 case $arg in codex:~/demo/) args+=("$REMOTE_DIR/") ;; *) args+=("$arg") ;; esac
done
exec "$REAL_RSYNC" "${args[@]}"
MOCK
chmod +x "$tmp/mock/rsync"
cd "$tmp/work/demo"
for direction in push pull; do
	if [[ $direction == push ]]; then
		src=$PWD
		dst=$REMOTE_DIR
	else
		src=$REMOTE_DIR
		dst=$PWD
	fi
	printf 'source\n' >"$src/newer"
	printf 'destination\n' >"$dst/newer"
	touch -t 202001010000 "$src/newer"
	touch -t 202101010000 "$dst/newer"
	printf 'delete\n' >"$dst/extra"
	run "$direction" -n --no-delete
	if grep -Fxq -- '- extra' "$tmp/out"; then exit 1; fi
	[[ -e $dst/extra ]]
	run "$direction"
	[[ $(cat "$dst/newer") == destination && ! -e $dst/extra ]]
	grep -Fxq -- '- extra' "$tmp/out"
	if grep -Fxq '~ newer' "$tmp/out"; then exit 1; fi
	grep -Fq '1 newer destination file(s)' "$tmp/err"
	run "$direction" -f
	[[ $(cat "$dst/newer") == source ]]
	grep -Fxq '~ newer' "$tmp/out"
	ok "$direction preserves newer destination, deletes destination-only files, force overwrites"
	printf 'cache/\n*.log\n' >.codexignore
	mkdir -p "$src/cache" "$dst/cache/.git" "$dst/cache/.ssh" "$dst/.git" "$dst/.ssh" "$dst/global"
	printf 'source secret\n' >"$src/cache/secret"
	printf 'destination secret\n' >"$dst/cache/secret"
	touch "$dst/cache/.git/config" "$dst/cache/.ssh/key" "$dst/.git/config" "$dst/.ssh/key" "$dst/cache/.codexignore" "$dst/global/a.log" "$dst/ordinary.log"
	printf 'global/\r\n' >"$XDG_CONFIG_HOME/codex-sync/ignore"
	run "$direction" -cn
	[[ -e $dst/cache/secret && -e $dst/ordinary.log ]]
	grep -Fq -- '- ' "$tmp/out"
	run "$direction" -c
	[[ ! -e $dst/cache/secret && ! -e $dst/ordinary.log ]]
	[[ -e $dst/cache/.git/config && -e $dst/cache/.ssh/key && -e $dst/cache/.codexignore && -e $dst/global/a.log && -e $dst/.git/config && -e $dst/.ssh/key ]]
	[[ $(cat "$src/cache/secret") == 'source secret' && -f .codexignore ]]
	ok "$direction cleanup deletes ignored destination files and protects nested built-ins, global rules and source"
	mkdir -p "$tmp/outside"
	printf 'outside\n' >"$tmp/outside/sentinel"
	ln -s "$tmp/outside" "$dst/link-cache"
	printf 'link-cache\n' >>.codexignore
	run "$direction" -c
	[[ ! -L $dst/link-cache && -e $tmp/outside/sentinel ]]
	ok "$direction cleanup unlinks ignored symlink without following it"
	printf '../outside/\n' >.codexignore
	reject "$direction" -c
	printf '+ dangerous\n' >.codexignore
	reject "$direction" -c
	printf '# codex-sync: no-global-ignore\n*.log\n' >.codexignore
	printf '!\n' >"$XDG_CONFIG_HOME/codex-sync/ignore"
	touch "$dst/disabled.log"
	run "$direction" -c
	[[ ! -e $dst/disabled.log ]]
	: >.codexignore
	: >"$XDG_CONFIG_HOME/codex-sync/ignore"
done
# Exercise rsync's actual filename escaping through the remote-operand adapter.
for name in 'space name' $'line\nbreak' 'literal\#012' $'tab\tname' 'pipe|name'; do
	printf 'name test\n' >"$name"
done
run push -nf
grep -Fxq '+ space name' "$tmp/out"
grep -Fxq '+ line\#012break' "$tmp/out"
grep -Fxq '+ literal\#134#012' "$tmp/out"
grep -Fxq $'+ tab\tname' "$tmp/out"
grep -Fxq '+ pipe|name' "$tmp/out"
[[ ! -e $REMOTE_DIR/space\ name ]]
ok 'real rsync preserves tabs and escapes newlines and literal backslashes without splitting names'
# Equal-mtime size changes and misleading names must not create newer warnings.
printf 'short\n' >newer-name
printf 'longer destination\n' >"$REMOTE_DIR/newer-name"
touch -t 202001010000 newer-name "$REMOTE_DIR/newer-name"
printf 'ordinary\n' >'file is newer'
run push -n
if grep -Fq 'newer destination file(s)' "$tmp/err"; then exit 1; fi
ok 'newer detection ignores filenames and equal-mtime size differences'
export FAIL_PROBE=1
if run push; then exit 1; fi
has --out-format=%i
grep -Fq 'Newer-file comparison failed' "$tmp/err"
unset FAIL_PROBE
export FAIL_APPLY=1
status=0
run pull -f || status=$?
[[ $status == 24 ]]
unset FAIL_APPLY
ok 'failed comparison blocks transfer and native transfer failure propagates'
reject push -c --no-delete
if run push -i </dev/null; then exit 1; fi
grep -Fq 'requires terminal' "$tmp/err"
run push -nqvp --no-progress --no-color
has --dry-run
has '--out-format=%i|%n'
if has --info=progress2; then exit 1; fi
run pull -nq
[[ ! -s $tmp/out ]]
run push -np
if has --info=progress2; then exit 1; fi
ok 'composable short flags, progress overrides, quiet, nonterminal interactive refusal'
if command -v script >/dev/null; then
	export CLI=$repo/bin/codex-sync
	printf 'pending\n' >"$REMOTE_DIR/interactive-extra"
	# shellcheck disable=SC2016
	printf 'n\n' | script -q -e -c '"$CLI" push -ic' /dev/null >"$tmp/terminal" && exit 1
	[[ -e $REMOTE_DIR/interactive-extra ]]
	# shellcheck disable=SC2016
	printf 'y\n' | script -q -e -c '"$CLI" push -ic' /dev/null >"$tmp/terminal"
	[[ ! -e $REMOTE_DIR/interactive-extra ]]
	ok 'interactive cleanup preview refuses by default and applies only after affirmation'
fi

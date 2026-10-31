#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=tests/helpers.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/helpers.sh"
unset NO_COLOR
cd "$tmp/work/demo"
cat >"$tmp/mock/rsync" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' CALL "$@" >>"$LOG.calls"
dry=false preview=false
for arg in "$@"; do
 case $arg in
 --dry-run) dry=true ;;
 '--out-format=%i|%n') preview=true ;;
 esac
done
if $dry; then
 for arg in "$@"; do [[ $arg != --info=progress2 ]] || exit 99; done
fi
if $preview; then
 [[ ${FAIL_PREVIEW:-0} != 1 ]] || exit 23
 printf '%s\n' '.d..t......|./' '.d..t......|existing/' \
 '>f+++++++++|space name' '>f.st......|changed' 'cd+++++++++|new dir/' \
 '*deleting  |old dir/' '*deleting  |old file' \
 '>f+++++++++|line\#012break' '>f+++++++++|literal\#134#012' \
 'cL+++++++++|link -> name'
elif ! $dry; then
 printf '%s\n' APPLY >>"$LOG.calls"
fi
MOCK
chmod +x "$tmp/mock/rsync"
for direction in push pull; do
	: >"$LOG.calls"
	run "$direction" -p
	grep -Fxq '+ space name' "$tmp/out"
	grep -Fxq '~ changed' "$tmp/out"
	grep -Fxq '+ new dir/' "$tmp/out"
	grep -Fxq -- '- old dir/' "$tmp/out"
	grep -Fxq '+ line\#012break' "$tmp/out"
	grep -Fxq '+ literal\#134#012' "$tmp/out"
	grep -Fxq '+ link -> name' "$tmp/out"
	grep -Fxq 'Preview: 5 added, 1 modified, 2 deleted' "$tmp/out"
	if grep -Fq 'existing/' "$tmp/out"; then exit 1; fi
	grep -Fxq APPLY "$LOG.calls"
	grep -Fxq -- --info=progress2 "$LOG.calls"
	ok "$direction automatically applies after concise escaped preview; transfer alone gets progress"
done
for flags in '-n' '-ni' '-nc' '-n --no-delete' '-nf'; do
	: >"$LOG.calls"
	read -r -a args <<<"$flags"
	run push "${args[@]}"
	if grep -Fxq APPLY "$LOG.calls"; then exit 1; fi
	grep -Fq 'Preview: ' "$tmp/out"
done
ok 'dry run and combined modes never apply'
run pull -nq
[[ ! -s $tmp/out ]]
run pull -nv
grep -Fxq '.d..t......|existing/' "$tmp/out"
ok 'quiet suppresses preview; verbose retains raw directory records'
export FAIL_PREVIEW=1
: >"$LOG.calls"
if run push -f; then exit 1; fi
if grep -Fxq APPLY "$LOG.calls"; then exit 1; fi
grep -Fq 'Preview failed' "$tmp/err"
unset FAIL_PREVIEW
ok 'preview failure blocks automatic transfer'
if command -v script >/dev/null; then
	export CLI=$repo/bin/codex-sync
	cat >"$tmp/mock/preview-runner" <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail
case $PREVIEW_OUTPUT in
terminal) exec "$CLI" "$PREVIEW_DIRECTION" -nf ;;
no-color) exec "$CLI" "$PREVIEW_DIRECTION" -nf --no-color ;;
redirected) exec "$CLI" "$PREVIEW_DIRECTION" -nf >"$PREVIEW_FILE" ;;
pipe) "$CLI" "$PREVIEW_DIRECTION" -nf | cat ;;
verbose) exec "$CLI" "$PREVIEW_DIRECTION" -nfv ;;
esac
RUNNER
	chmod +x "$tmp/mock/preview-runner"
	export PREVIEW_DIRECTION PREVIEW_OUTPUT PREVIEW_FILE=$tmp/redirected
	escape=$'\033'
	for PREVIEW_DIRECTION in push pull; do
		run "$PREVIEW_DIRECTION" -nf
		[[ $(cat "$tmp/out") != *"$escape"* ]]
		sed -e "s/^+ /${escape}[32m+${escape}[0m /" \
			-e "s/^- /${escape}[31m-${escape}[0m /" \
			-e "s/^~ /${escape}[33m~${escape}[0m /" "$tmp/out" >"$tmp/expected"
		PREVIEW_OUTPUT=terminal script -q -e -c preview-runner /dev/null >"$tmp/terminal"
		tr -d '\r' <"$tmp/terminal" >"$tmp/actual"
		cmp "$tmp/expected" "$tmp/actual"
		for PREVIEW_OUTPUT in no-color redirected pipe; do
			script -q -e -c preview-runner /dev/null >"$tmp/terminal"
			if [[ $PREVIEW_OUTPUT == redirected ]]; then
				cmp "$tmp/out" "$PREVIEW_FILE"
			else
				tr -d '\r' <"$tmp/terminal" >"$tmp/actual"
				cmp "$tmp/out" "$tmp/actual"
			fi
		done
		for value in '' 1; do
			NO_COLOR=$value PREVIEW_OUTPUT=terminal script -q -e -c preview-runner /dev/null >"$tmp/terminal"
			tr -d '\r' <"$tmp/terminal" >"$tmp/actual"
			cmp "$tmp/out" "$tmp/actual"
		done
		PREVIEW_OUTPUT=verbose script -q -e -c preview-runner /dev/null >"$tmp/terminal"
		[[ $(cat "$tmp/terminal") != *"$escape"* ]]
	done
	ok 'terminal previews color only symbols; no-color, NO_COLOR, pipes, redirection and verbose stay plain'
	: >"$LOG.calls"
	# shellcheck disable=SC2016
	if printf 'n\n' | script -q -e -c '"$CLI" push -iq' /dev/null >"$tmp/terminal"; then exit 1; fi
	grep -Fq 'Preview: ' "$tmp/terminal"
	if grep -Fxq APPLY "$LOG.calls"; then exit 1; fi
	ok 'quiet interactive preview is visible and refusal never applies'
fi

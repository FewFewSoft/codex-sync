#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=tests/helpers.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/helpers.sh"
fixture=$tmp/release
mkdir -p "$fixture/bin"
cp "$repo/release.sh" "$fixture/"
export FIXTURE=$fixture
cat >"$tmp/mock/git" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$LOG.git"
case $1 in
 rev-parse) [[ ${2:-} != --show-toplevel ]] || { echo "${MOCK_ROOT:-$FIXTURE}"; exit; }; echo abc ;;
 symbolic-ref) echo "${BRANCH:-main}" ;;
 status) printf '%s' "${DIRTY:-}" ;;
 ls-files) exit 0 ;;
 remote) [[ ${BAD_REMOTE:-0} == 0 ]] || exit 1; echo local-origin ;;
 tag)
  [[ ${LOCAL_TAG:-0} == 0 ]] || echo "$3"
  ;;
 ls-remote)
  [[ ${UNREACHABLE:-0} == 0 ]] || exit 1
  [[ ${MISSING_MAIN:-0} == 1 ]] || printf 'abc\trefs/heads/main\n'
  [[ ${REMOTE_TAG:-0} == 0 ]] || printf 'abc\trefs/tags/1.2.4\n'
  ;;
 add|commit|-c|push)
  printf '%s\n' "$*" >> "$LOG.mutations"
  step=$1
  [[ ${2:-} != push.followTags=false ]] || step=push
  [[ $step != "${FAIL_STEP:-none}" ]]
  ;;
 *) exit 1 ;;
esac
MOCK
chmod +x "$tmp/mock/git"
reset_fixture() {
	printf '#!/usr/bin/env bash\nreadonly VERSION=1.2.3\nreadonly BUILD_METADATA=\x27\x27\n' >"$fixture/bin/codex-sync"
	cp "$fixture/bin/codex-sync" "$tmp/before"
	rm -f "$LOG.git" "$LOG.mutations"
}
invoke() { bash "$fixture/release.sh" "$@" >"$tmp/out" 2>&1; }
reject_release() {
	if invoke "$@" <<<yes; then
		cat "$tmp/out"
		exit 1
	fi
	[[ ! -e $LOG.mutations ]]
	cmp "$tmp/before" "$fixture/bin/codex-sync"
}
for bump in major minor patch; do
	reset_fixture
	invoke "$bump" <<<yes
	case $bump in major) target=2.0.0 ;; minor) target=1.3.0 ;; patch) target=1.2.4 ;; esac
	sed "s/readonly VERSION=1.2.3/readonly VERSION=$target/" "$tmp/before" >"$tmp/expected"
	cmp "$tmp/expected" "$fixture/bin/codex-sync"
	cat >"$tmp/expected-log" <<LOG
add -- bin/codex-sync
commit -m build: bump version
-c tag.gpgSign=false tag -a $target -m $target
-c push.followTags=false push --atomic origin refs/heads/main:refs/heads/main refs/tags/$target:refs/tags/$target
LOG
	cmp "$tmp/expected-log" "$LOG.mutations"
done
ok 'SemVer bumps, only canonical bytes changed, annotated tag and atomic push arguments'
reset_fixture
invoke <<<$'patch\nyes'
grep -q 'Choose bump' "$tmp/out"
for answer in '' no invalid; do
	reset_fixture
	invoke patch <<<"$answer"
	[[ ! -e $LOG.mutations ]]
	cmp "$tmp/before" "$fixture/bin/codex-sync"
done
reset_fixture
invoke patch </dev/null
[[ ! -e $LOG.mutations ]]
reset_fixture
sed -i 's/1.2.3/1.2.999999999999999999999999/' "$fixture/bin/codex-sync"
invoke patch <<<yes
grep -qx 'readonly VERSION=1.2.1000000000000000000000000' "$fixture/bin/codex-sync"
ok 'interactive selection and default-No cancellation including EOF'
for condition in 'MOCK_ROOT=/different-root' 'MISSING_MAIN=1' 'BRANCH=topic' 'BRANCH=HEAD' 'DIRTY=?? untracked' 'LOCAL_TAG=1' 'REMOTE_TAG=1' 'BAD_REMOTE=1' 'UNREACHABLE=1'; do
	reset_fixture
	export "${condition?}"
	reject_release patch
	unset "${condition%%=*}"
done
reset_fixture
reject_release invalid
reject_release patch extra
# shellcheck disable=SC2016
printf 'readonly VERSION=$(touch malicious)\n' >"$fixture/bin/codex-sync"
cp "$fixture/bin/codex-sync" "$tmp/before"
reject_release patch
[[ ! -e $fixture/malicious ]]
reset_fixture
printf 'readonly VERSION=1.2.3\n' >>"$fixture/bin/codex-sync"
cp "$fixture/bin/codex-sync" "$tmp/before"
reject_release patch
ok 'branch, dirt, tags, remote, arguments and unsafe VERSION reject before mutation'
for step in commit -c push; do
	reset_fixture
	export FAIL_STEP=$step
	if invoke patch <<<yes; then exit 1; fi
	case $step in
	commit) ! grep -q '^push\|^-c' "$LOG.mutations" ;;
	-c) ! grep -q 'push --atomic' "$LOG.mutations" ;;
	push) grep -q 'local commit and tag remain' "$tmp/out" ;;
	esac
	unset FAIL_STEP
done
ok 'mutation failures stop with no force, retries or destructive rollback'

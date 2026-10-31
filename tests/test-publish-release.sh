#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=tests/helpers.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/helpers.sh"
mkdir -p "$tmp/source/scripts" "$tmp/source/bin" "$tmp/source/dist"
cp "$repo/scripts/publish-release.sh" "$repo/scripts/release-version.sh" "$tmp/source/scripts/"
cp "$repo/bin/codex-sync" "$tmp/source/bin/"
export RELEASE_TAG COMMIT=abc123 GH_REPO=example/codex-sync EXPECTED_SHA256
RELEASE_TAG=$(canonical_version "$tmp/source/bin/codex-sync")
archive="dist/codex-sync-$RELEASE_TAG.run"
cd "$tmp/source"
printf 'installer bytes\n' >"$archive"
EXPECTED_SHA256=$(sha256sum "$archive")
EXPECTED_SHA256=${EXPECTED_SHA256%% *}
export REMOTE_COMMIT=$COMMIT RELEASE_STATE=true STILL_DRAFT=true LOOKUP_FAIL=0
cat >"$tmp/mock/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$LOG.gh"
case "$*" in
"api repos/$GH_REPO/commits/$RELEASE_TAG --jq .sha") printf '%s\n' "$REMOTE_COMMIT" ;;
"api --paginate repos/$GH_REPO/releases "*)
    [[ $LOOKUP_FAIL == 0 ]] || exit 1
    printf '%s\n' "$RELEASE_STATE"
    ;;
"release view $RELEASE_TAG --json isDraft --jq .isDraft") printf '%s\n' "$STILL_DRAFT" ;;
"release upload $RELEASE_TAG dist/codex-sync-$RELEASE_TAG.run --clobber") ;;
"release create $RELEASE_TAG dist/codex-sync-$RELEASE_TAG.run --verify-tag --target $COMMIT --draft --title $RELEASE_TAG") ;;
*) exit 1 ;;
esac
MOCK
chmod +x "$tmp/mock/gh"
publish() {
	: >"$LOG.gh"
	bash scripts/publish-release.sh >"$tmp/out" 2>&1
}
refuse() {
	if publish; then
		echo 'Unexpected publication success' >&2
		exit 1
	fi
	if grep -Eq '^release (upload|create|edit) ' "$LOG.gh"; then exit 1; fi
}
publish
grep -Fx "release upload $RELEASE_TAG $archive --clobber" "$LOG.gh"
if grep -q '^release edit ' "$LOG.gh"; then exit 1; fi
COMMIT=def456 REMOTE_COMMIT=def456 publish
grep -Fx "release upload $RELEASE_TAG $archive --clobber" "$LOG.gh"
ok 'draft and retagged reruns replace the asset without editing metadata'
RELEASE_STATE='' publish
grep -Fx "release create $RELEASE_TAG $archive --verify-tag --target $COMMIT --draft --title $RELEASE_TAG" "$LOG.gh"
ok 'absent release creates a verified draft for the triggering commit'
RELEASE_STATE=false refuse
STILL_DRAFT=false refuse
RELEASE_STATE=unexpected refuse
LOOKUP_FAIL=1 refuse
REMOTE_COMMIT=other refuse
ok 'published releases, changed draft state, lookup errors and moved tags block writes'
EXPECTED_SHA256=invalid refuse
EXPECTED_SHA256=$(printf '%064d' 0) refuse
printf 'altered\n' >>"$archive"
refuse
printf 'installer bytes\n' >"$archive"
mv "$archive" "$tmp/installer"
refuse
ln -s "$tmp/installer" "$archive"
refuse
rm "$archive"
cp "$tmp/installer" "$archive"
RELEASE_TAG=999.999.999 refuse
ok 'digest, archive and canonical version validation block writes'

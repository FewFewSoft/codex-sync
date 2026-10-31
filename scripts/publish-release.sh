#!/usr/bin/env bash
set -euo pipefail
base=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
: "${RELEASE_TAG:?}" "${COMMIT:?}" "${EXPECTED_SHA256:?}" "${GH_REPO:?}"
bash "$base/scripts/release-version.sh" "$RELEASE_TAG"
[[ $EXPECTED_SHA256 =~ ^[0-9a-f]{64}$ ]]
archive="dist/codex-sync-$RELEASE_TAG.run"
[[ -f $archive && ! -L $archive ]]
printf '%s  %s\n' "$EXPECTED_SHA256" "$archive" | sha256sum --check --strict
[[ $(gh api "repos/$GH_REPO/commits/$RELEASE_TAG" --jq .sha) == "$COMMIT" ]] || {
	echo 'Remote tag no longer points to the triggering commit; refusing release changes.' >&2
	exit 1
}
draft=$(gh api --paginate "repos/$GH_REPO/releases" \
	--jq ".[] | select(.tag_name == \"$RELEASE_TAG\") | .draft")
case $draft in
true)
	[[ $(gh release view "$RELEASE_TAG" --json isDraft --jq .isDraft) == true ]] || {
		echo 'Release is no longer a draft; refusing asset replacement.' >&2
		exit 1
	}
	gh release upload "$RELEASE_TAG" "$archive" --clobber
	;;
false)
	echo 'Release is already published; refusing to change metadata or assets.' >&2
	exit 1
	;;
'')
	gh release create "$RELEASE_TAG" "$archive" \
		--verify-tag --target "$COMMIT" --draft --title "$RELEASE_TAG"
	;;
*)
	echo 'Unexpected release lookup response; refusing release changes.' >&2
	exit 1
	;;
esac

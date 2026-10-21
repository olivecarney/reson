#!/bin/bash
# Run only on trusted main builds, after downloading this run's verified artifact.
set -euo pipefail
cd "$(dirname "$0")/.."
reson_version="${1:?Expected app version}"
reson_commit="${2:?Expected source commit}"
: "${GH_REPO:?Expected owner/repository}"
if [[ ! "$reson_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$reson_commit" =~ ^[0-9a-f]{40}$ ]]; then
    echo 'Expected a stable app version and a full commit SHA' >&2
    exit 1
fi
reson_tag="v$reson_version"
if reson_draft=$(gh release view "$reson_tag" --json isDraft --jq .isDraft 2>/dev/null); then
    if [[ "$reson_draft" == true ]]; then
        echo "A draft for $reson_tag exists; finish or delete it before retrying." >&2
        exit 1
    fi
    echo "$reson_tag is already published; leaving it unchanged."
    exit 0
fi
# A missing commit endpoint returns error JSON on stdout. Query refs first so
# absence is an empty successful response and API failures remain fatal.
reson_ref=$(gh api "repos/$GH_REPO/git/matching-refs/tags/$reson_tag" \
    --jq ".[] | select(.ref == \"refs/tags/$reson_tag\") | .ref")
if [[ -n "$reson_ref" ]]; then
    reson_existing=$(gh api "repos/$GH_REPO/commits/$reson_tag" --jq .sha)
    if [[ "$reson_existing" != "$reson_commit" ]]; then
        echo "$reson_tag points to another commit; use a new version." >&2
        exit 1
    fi
fi
reson_image="Reson-$reson_version-macos-arm64.dmg"
(cd build/dist && sha256sum -c "$reson_image.sha256")
gh release create "$reson_tag" "build/dist/$reson_image" "build/dist/$reson_image.sha256" \
    --target "$reson_commit" --title "Reson $reson_tag" \
    --notes-file docs/release-notes.md --generate-notes

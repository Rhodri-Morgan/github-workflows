#!/bin/sh

set -e

# Fetch latest tags from remote; ignore failures caused by local tag conflicts.
git fetch --tags || true

TODAY=$(date -u +%Y.%m.%d)
BASE_TAG="v${TODAY}"
EXISTING_TAGS=$(git tag -l "${BASE_TAG}*" | sort -V)

if [ -z "$EXISTING_TAGS" ]; then
    NEXT_TAG="$BASE_TAG"
else
    LATEST_TAG=$(echo "$EXISTING_TAGS" | tail -n1)

    if [ "$LATEST_TAG" = "$BASE_TAG" ]; then
        NEXT_TAG="${BASE_TAG}-1"
    else
        SUFFIX=$(echo "$LATEST_TAG" | sed "s/${BASE_TAG}-//")
        case "$SUFFIX" in
            ''|*[!0-9]*) NEXT_TAG="${BASE_TAG}-1" ;;
            *) NEXT_NUM=$((SUFFIX + 1)); NEXT_TAG="${BASE_TAG}-${NEXT_NUM}" ;;
        esac
    fi
fi

echo "Creating tag: $NEXT_TAG"

git tag -a "$NEXT_TAG" -m "Release $NEXT_TAG"
git push origin "$NEXT_TAG"

echo "Tag $NEXT_TAG created and pushed successfully"

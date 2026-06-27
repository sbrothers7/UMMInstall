#!/bin/bash
#
# release.sh — build, tag, and publish a GitHub release.
#
#   ./release.sh 1.0.7     # build & release v1.0.7
#   ./release.sh           # bump the patch of the latest release and release that
#
# Builds the app via swift/build.sh with the given version, zips the resulting
# .app into swift/Installer.zip, creates+pushes the git tag if missing, and
# publishes (or updates) the GitHub release with that asset.
set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# 1. Resolve the version: first argument, else bump the patch of the latest
#    GitHub release.
# ---------------------------------------------------------------------------
VERSION="$1"
if [ -z "$VERSION" ]; then
    LATEST="$(gh release view --json tagName -q .tagName 2>/dev/null || true)"
    if [ -z "$LATEST" ]; then
        echo "No version given and no existing release to bump from." >&2
        echo "Usage: ./release.sh <version>   (e.g. ./release.sh 1.0.7)" >&2
        exit 1
    fi
    BASE="${LATEST#v}"
    MAJOR="${BASE%%.*}"
    REST="${BASE#*.}"
    MINOR="${REST%%.*}"
    PATCH="${REST#*.}"
    PATCH="${PATCH%%.*}"
    VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
    echo "No version given — bumping $LATEST → v$VERSION"
fi
VERSION="${VERSION#v}"
TAG="v$VERSION"

# ---------------------------------------------------------------------------
# 2. Sanity checks.
# ---------------------------------------------------------------------------
command -v gh >/dev/null 2>&1 || { echo "error: gh (GitHub CLI) is required." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "error: run 'gh auth login' first." >&2; exit 1; }

if [ -n "$(git status --porcelain)" ]; then
    echo "warning: working tree has uncommitted changes; the tag will point at the last commit."
fi

# ---------------------------------------------------------------------------
# 3. Build via swift/build.sh.
# ---------------------------------------------------------------------------
echo "Building $TAG..."
( cd swift && ./build.sh --version "$VERSION" )

APP="swift/macOS ADOFAI Mod Installer.app"
if [ ! -d "$APP" ]; then
    echo "error: build did not produce \"$APP\"." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 4. Zip the .app into Installer.zip.
# ---------------------------------------------------------------------------
ZIP="swift/Installer.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Packaged: $ZIP"

# ---------------------------------------------------------------------------
# 5. Create + push the tag if it doesn't already exist.
# ---------------------------------------------------------------------------
if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "Creating tag $TAG..."
    git tag "$TAG"
    git push origin "$TAG"
else
    echo "Tag $TAG already exists."
fi

# ---------------------------------------------------------------------------
# 6. Publish (or update) the GitHub release with the asset.
# ---------------------------------------------------------------------------
NOTES="### Installation | 설치 방법
[![Downloads](https://img.shields.io/github/downloads/sbrothers7/UMMInstall/total?style=flat-square&logo=github&label=Downloads&color=2ea44f)]()

Unzip the Installer.zip, then open the resulting app
Installer.zip을 압축 해제 후 설치기 앱을 실행해주세요

> [!Important]
> When opening the .app, open via \`Right Click > Open\`
> .app 파일을 열 때 \`우클릭 > 열기\`로 열어주세요
>
> If it still doesn't open, go to \`System Settings > Privacy & Security > Open Anyway\`"

if gh release view "$TAG" >/dev/null 2>&1; then
    echo "Release $TAG exists — updating asset..."
    gh release upload "$TAG" "$ZIP" --clobber
else
    echo "Creating release $TAG..."
    gh release create "$TAG" "$ZIP" --title "$TAG" --notes "$NOTES"
fi

echo "Done: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/tag/$TAG"

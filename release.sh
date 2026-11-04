#!/bin/bash
#
# release.sh — tag a v2 release and leave it on GitHub as a draft.
#
#   ./release.sh 2.2.0       # release v2.2.0
#   ./release.sh             # bump the patch of the latest release
#   ./release.sh -n 2.2.0    # dry run: check and print the plan, change nothing
#   ./release.sh --no-wait   # don't wait for the builds
#
# Sets appVersion and the GUI's pubspec version, commits and pushes that to
# v2, creates a draft release with notes drafted from the commits since the
# last release, then pushes the tag. The tag starts the "Release GUI (v2)"
# workflow, which builds the GUI and amm and uploads them to the draft.
# Write the "What's new" section and publish the draft on GitHub when ready.
set -euo pipefail

cd "$(dirname "$0")"

BRANCH=v2
WORKFLOW=release-gui.yml
VERSION_FILE=core/lib/src/version.dart
PUBSPEC=gui/pubspec.yaml
# What the workflow uploads; the updaters look for these names.
ASSETS=(Installer-macos.zip Installer-linux.tar.gz amm-darwin-arm64 amm-darwin-x64 amm-linux-x64)

DRY=false
WAIT=true
VERSION=""
for arg in "$@"; do
    case "$arg" in
        -n|--dry-run) DRY=true ;;
        --no-wait) WAIT=false ;;
        -h|--help) sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "error: unknown option $arg" >&2; exit 2 ;;
        *) VERSION="$arg" ;;
    esac
done

die() { echo "error: $*" >&2; exit 1; }
run() { if $DRY; then echo "  would run: $*"; else "$@"; fi; }

command -v gh >/dev/null || die "gh (GitHub CLI) is required."
gh auth status >/dev/null 2>&1 || die "run 'gh auth login' first."

# --- Version: the argument, else the latest release's patch + 1. ---
LATEST="$(gh release view --json tagName -q .tagName 2>/dev/null || true)"
if [ -z "$VERSION" ]; then
    [ -n "$LATEST" ] || die "no version given and no release to bump from."
    IFS=. read -r MA MI PA <<<"${LATEST#v}"
    VERSION="$MA.$MI.$((PA + 1))"
    echo "No version given: $LATEST → v$VERSION"
fi
VERSION="${VERSION#v}"
TAG="v$VERSION"
[[ "$VERSION" =~ ^2\.[0-9]+\.[0-9]+$ ]] || die "$VERSION isn't a v2 version like 2.2.0 (the workflow only builds v2.* tags)."

# --- The tree must be the pushed v2, and the tag new. ---
[ "$(git branch --show-current)" = "$BRANCH" ] || die "check out $BRANCH first."
[ -z "$(git status --porcelain)" ] || die "commit or stash your changes first."
git fetch -q origin "$BRANCH" --tags
[ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$BRANCH")" ] ||
    die "$BRANCH differs from origin/$BRANCH; pull or push first."
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null ||
    [ -n "$(git ls-remote --tags origin "refs/tags/$TAG")" ]; then
    die "tag $TAG already exists."
fi
gh release view "$TAG" >/dev/null 2>&1 && die "a release for $TAG already exists (maybe a draft)."
if [ -n "$LATEST" ]; then
    NEWEST="$(printf '%s\n%s\n' "${LATEST#v}" "$VERSION" | sort -V | tail -1)"
    { [ "$NEWEST" = "$VERSION" ] && [ "${LATEST#v}" != "$VERSION" ]; } ||
        die "$TAG isn't newer than the latest release $LATEST; the updaters would never offer it."
fi

# --- Notes: the commits since the last release, for you to rewrite. ---
PREV="$(git describe --tags --abbrev=0 --match 'v2.*' 2>/dev/null || true)"
CHANGES="$(git log --no-merges --format='- %s' ${PREV:+"$PREV"..HEAD})"
NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
cat >"$NOTES" <<EOF
### What's new | 새로운 기능
<!-- Draft from the commits since ${PREV:-the start}; rewrite in English and Korean before publishing. -->
${CHANGES:-- (no commits)}

### Installation | 설치 방법
[![Downloads](https://img.shields.io/github/downloads/sbrothers7/UMMInstall/total?style=flat-square&logo=github&label=Downloads&color=2ea44f)]()

- macOS: \`Installer-macos.zip\`
- Linux (x64): \`Installer-linux.tar.gz\`
- Command line: \`curl -fsSL https://raw.githubusercontent.com/sbrothers7/UMMInstall/v2/cli/install.sh | bash\`, or \`amm update\`

Unzip Installer-macos.zip, then open the resulting app
Installer-macos.zip을 압축 해제 후 설치기 앱을 실행해주세요

> [!Important]
> When opening the .app, open via \`Right Click > Open\`
> .app 파일을 열 때 \`우클릭 > 열기\`로 열어주세요
>
> If it still doesn't open, go to \`System Settings > Privacy & Security > Open Anyway\`
> 그래도 안 열린다면 \`시스템 설정 > 개인정보 보호 및 보안 > 그래도 열기\` 버튼을 눌러주세요.
EOF

echo "Releasing $TAG (previous: ${PREV:-none})"
if $DRY; then
    echo "--- draft notes ---"
    cat "$NOTES"
    echo "-------------------"
fi

# --- Bump the versions the updaters compare (and the workflow checks). ---
# The pubspec build number goes up by one each release.
BUILD="$(sed -n 's/^version: [0-9.]*+\([0-9]*\)$/\1/p' "$PUBSPEC")"
BUILD=$(( ${BUILD:-0} + 1 ))
echo "Setting appVersion and $PUBSPEC to $VERSION+$BUILD"
if ! $DRY; then
    sed -i.bak "s/^const appVersion = '.*';/const appVersion = '$VERSION';/" "$VERSION_FILE"
    sed -i.bak "s/^version: .*/version: $VERSION+$BUILD/" "$PUBSPEC"
    rm -f "$VERSION_FILE.bak" "$PUBSPEC.bak"
    grep -qx "const appVersion = '$VERSION';" "$VERSION_FILE" || die "couldn't set appVersion."
    grep -qx "version: $VERSION+$BUILD" "$PUBSPEC" || die "couldn't set the pubspec version."
fi
if $DRY || ! git diff --quiet; then
    run git commit -q -am "Release $TAG"
fi
run git push -q origin "$BRANCH"
SHA="$(git rev-parse HEAD)"

# --- The draft first, so the workflow uploads into it. ---
run gh release create "$TAG" --draft --target "$SHA" --title "$TAG" --notes-file "$NOTES"
run git tag "$TAG" "$SHA"
run git push -q origin "$TAG"

URL="https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases"
if $DRY; then
    echo "Dry run: nothing changed."
    exit 0
fi
if ! $WAIT; then
    echo "Draft created; the builds upload to it when they finish: $URL"
    exit 0
fi

# --- Wait for the builds, then check every file reached the draft. ---
echo "Waiting for the $WORKFLOW run..."
RUN=""
for _ in $(seq 1 30); do
    RUN="$(gh run list --workflow "$WORKFLOW" --event push --limit 10 \
        --json databaseId,headSha,headBranch \
        -q ".[] | select(.headSha == \"$SHA\" and .headBranch == \"$TAG\") | .databaseId" | head -1)"
    [ -n "$RUN" ] && break
    sleep 5
done
[ -n "$RUN" ] || die "no $WORKFLOW run started for $TAG; check $URL and the Actions tab."
gh run watch "$RUN" --exit-status >/dev/null ||
    die "the build failed: $(gh run view "$RUN" --json url -q .url)"

HAVE="$(gh release view "$TAG" --json assets -q '.assets[].name')"
MISSING=()
for a in "${ASSETS[@]}"; do
    grep -qx "$a" <<<"$HAVE" || MISSING+=("$a")
done
[ ${#MISSING[@]} -eq 0 ] || die "the draft is missing ${MISSING[*]}."
DRAFT="$(gh release view "$TAG" --json isDraft -q .isDraft)"
[ "$DRAFT" = true ] || die "$TAG is no longer a draft; check $URL."

echo "Draft $TAG is ready with all ${#ASSETS[@]} files."
echo "Write the notes and publish it: $URL"

#!/usr/bin/env bash
#
# Publishes the version currently in VERSION (`make release`).
#
# The release itself is built by GitHub Actions (`.github/workflows/release.yml`)
# from the tag push, so this script only has to: prove the tree is releasable,
# prove it is green, tag it, and push the tag. Nothing is uploaded from the
# local machine, and no build output is committed.
#
#   ./scripts/release.sh            verify, tag vX.Y.Z, push the branch and tag
#
# Use `--dry-run` to stop right before the tag is created.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *)
      echo "!! Unknown argument: $arg" >&2
      echo "   Usage: $0 [--dry-run]" >&2
      exit 1
      ;;
  esac
done

VERSION_SEMVER="$(tr -d '[:space:]' < VERSION)"
TAG="v${VERSION_SEMVER}"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"

if [[ ! "$VERSION_SEMVER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "!! VERSION does not hold a bare semver: '$VERSION_SEMVER'" >&2
  exit 1
fi

# Everything must already be committed: a release tag has to point at a commit.
if [[ -n "$(git status --porcelain)" ]]; then
  echo "!! The working tree is dirty; commit the release first:" >&2
  git status --short >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  echo "!! Tag $TAG already exists. Bump VERSION before releasing again." >&2
  exit 1
fi

echo "==> Releasing $TAG from $BRANCH"
echo
echo "==> Documentation consistency"
./scripts/check-docs.sh
echo
echo "==> Verification suite"
./scripts/verify.sh
echo

if ((DRY_RUN)); then
  echo "--dry-run: stopping before the tag is created. Everything is green."
  exit 0
fi

echo "==> Pushing $BRANCH"
git push origin "$BRANCH"

echo "==> Tagging $TAG"
git tag -a "$TAG" -m "Pi Web Desktop $TAG"

echo "==> Pushing $TAG"
git push origin "$TAG"

cat <<EOF

$TAG was pushed. GitHub Actions now builds the universal app bundle from this
tag and publishes the release:
  https://github.com/bestxia0/pi-web-desktop-macos/actions/workflows/release.yml

Watch it with:
  gh run watch \$(gh run list --workflow=release.yml --limit 1 --json databaseId --jq '.[0].databaseId')
EOF

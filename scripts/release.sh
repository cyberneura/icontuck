#!/usr/bin/env bash
# Bumps the version, pushes it, then triggers the Release workflow and watches it.
#   ./scripts/release.sh [patch|minor|major]   (default: patch)
#
#   1. Verify the working tree is clean and HEAD == origin/main
#   2. Compute the next version from MARKETING_VERSION
#   3. Rewrite MARKETING_VERSION and CURRENT_PROJECT_VERSION, commit, push
#   4. Trigger the workflow and watch it
#
# The version is incremented on every release because re-running the workflow on
# an already published version collides with the existing tag. Automating the
# bump removes the "forgot to bump" failure mode entirely.
#
# Requires an authenticated gh CLI.
set -euo pipefail

cd "$(dirname "$0")/.."

BUMP="${1:-patch}"
case "${BUMP}" in
  patch | minor | major) ;;
  *)
    echo "Usage: ./scripts/release.sh [patch|minor|major]  (default: patch)" >&2
    exit 1
    ;;
esac

# Check gh before anything is rewritten. If the push lands but the trigger cannot
# run, the bump commit sits on main without a build, and the next run would pick a
# different version — leaving a version that is never published.
if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh CLI not found. Install it and run 'gh auth login'." >&2
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "Error: gh is not authenticated. Run 'gh auth login'." >&2
  exit 1
fi

# Only number a release from a clean main. The build runs against origin/main, so
# anything uncommitted here would silently not be in the artifact.
if [ "$(git branch --show-current)" != "main" ]; then
  echo "Error: not on the 'main' branch. Switch to main first." >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "Error: working tree is not clean. Commit or stash your changes first." >&2
  exit 1
fi
git fetch origin +main:refs/remotes/origin/main
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
  echo "Error: local HEAD does not match origin/main. Push (or pull) first." >&2
  exit 1
fi

CURRENT=$(./scripts/version.sh)
if ! printf '%s' "${CURRENT}" | grep -qE '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
  echo "Error: current MARKETING_VERSION is not X.Y.Z: ${CURRENT}" >&2
  exit 1
fi

IFS=. read -r MAJOR MINOR PATCH <<< "${CURRENT}"
case "${BUMP}" in
  major) VERSION="$((MAJOR + 1)).0.0" ;;
  minor) VERSION="${MAJOR}.$((MINOR + 1)).0" ;;
  patch) VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))" ;;
esac

# CFBundleVersion has to increase monotonically across releases. The commit count
# supplies the number (+1 for the release commit this script is about to create,
# so it matches the commit that carries it), but it does NOT guarantee the
# increase on its own: it counts the depth of this clone's history, so a shallow
# clone or a rewritten main hands back a smaller number than the last release
# used, and every guard above still passes. Compare against the value already in
# the project rather than trusting git.
PREVIOUS_BUILD=$(./scripts/version.sh build)
# Same shape as the Xcode guard in the workflow: `[ "1.2" -le ... ]` exits 2,
# which an `if` reads as false, so the comparison has to be reached with an
# integer or not at all.
case "${PREVIOUS_BUILD}" in
  '' | *[!0-9]*)
    echo "Error: CURRENT_PROJECT_VERSION is not an integer: ${PREVIOUS_BUILD}" >&2
    exit 1
    ;;
esac
BUILD_NUMBER=$(( $(git rev-list --count HEAD) + 1 ))
if [ "${BUILD_NUMBER}" -le "${PREVIOUS_BUILD}" ]; then
  echo "Error: build number ${BUILD_NUMBER} would not increase (previous: ${PREVIOUS_BUILD})." >&2
  echo "  git rev-list --count HEAD counts this clone's history depth." >&2
  echo "  A shallow clone or a rewritten main breaks the assumption." >&2
  echo "  Check with: git rev-parse --is-shallow-repository" >&2
  exit 1
fi

echo "Bumping version: ${CURRENT} -> ${VERSION} (${BUMP}), build ${BUILD_NUMBER}"

PBXPROJ=Icontuck.xcodeproj/project.pbxproj

# version.sh accepts a quoted value, so both rewrites have to match one too.
# Handling quotes on the read side alone is worse than not handling them at all: a
# project mixing quoted and unquoted configurations would be rewritten in part,
# fail the verification below, and leave the working tree dirty. Either way the
# value is written back unquoted. Dots are escaped because the version goes into a
# regular expression.
CURRENT_RE=$(printf '%s' "${CURRENT}" | sed 's/\./\\./g')
MARKETING_COUNT=$(grep -cE "MARKETING_VERSION = \"?${CURRENT_RE}\"?;" "${PBXPROJ}" || true)
if [ "${MARKETING_COUNT}" -eq 0 ]; then
  echo "Error: no 'MARKETING_VERSION = ${CURRENT};' entries in ${PBXPROJ}" >&2
  exit 1
fi
sed -i '' -E \
  -e "s/MARKETING_VERSION = \"?${CURRENT_RE}\"?;/MARKETING_VERSION = ${VERSION};/g" \
  -e "s/CURRENT_PROJECT_VERSION = \"?[0-9]+\"?;/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER};/g" \
  "${PBXPROJ}"

# version.sh also fails when the configurations disagree, so this catches a sed
# that only reached some of them.
if [ "$(./scripts/version.sh)" != "${VERSION}" ]; then
  echo "Error: MARKETING_VERSION rewrite did not take effect. Check ${PBXPROJ}." >&2
  exit 1
fi
if [ "$(./scripts/version.sh build)" != "${BUILD_NUMBER}" ]; then
  echo "Error: CURRENT_PROJECT_VERSION rewrite did not take effect. Check ${PBXPROJ}." >&2
  exit 1
fi

git add "${PBXPROJ}"
git commit -m "chore: release v${VERSION}"
if ! git push origin HEAD:main; then
  echo "Error: push failed. The local release commit remains." >&2
  echo "  Undo it:  git reset --hard origin/main" >&2
  echo "  Or retry: git push origin HEAD:main" >&2
  exit 1
fi

echo "Triggering release build for v${VERSION} ..."

# workflow_dispatch does not return a run id, so poll for it. Match on the commit
# just pushed rather than "the newest run", so a concurrent dispatch of a
# different version is not mistaken for this one. This does not disambiguate a
# manual re-dispatch of the same commit: those share a headSha, and `.[0]` takes
# whichever the API happens to return first — gh does not promise an order.
# Re-dispatching by hand while this script is waiting may watch the wrong run.
RELEASE_SHA=$(git rev-parse HEAD)

if ! gh workflow run release.yml --ref main; then
  echo "Error: failed to trigger the workflow. v${VERSION} is already pushed to main." >&2
  echo "  Retry with: gh workflow run release.yml --ref main" >&2
  exit 1
fi

# `|| true` keeps a transient API error from killing the wait loop through set -e;
# a failed poll just means "not visible yet". 60 x 2s = up to 2 minutes, because
# the run list API can lag behind an accepted dispatch by more than a few seconds.
RUN_ID=""
for _ in $(seq 1 60); do
  sleep 2
  RUN_ID=$(gh run list --workflow=release.yml --branch main --limit 20 \
    --json databaseId,headSha \
    --jq "[.[] | select(.headSha == \"${RELEASE_SHA}\")] | .[0].databaseId // \"\"" \
    2>/dev/null || true)
  if [ -n "${RUN_ID}" ]; then
    break
  fi
done
if [ -z "${RUN_ID}" ]; then
  echo "Error: could not find the triggered workflow run within 2 minutes." >&2
  echo "  The build may still be running. Check it with:" >&2
  echo "    gh run list --workflow=release.yml" >&2
  exit 1
fi
echo "Watching run ${RUN_ID} ..."
gh run watch "${RUN_ID}" --exit-status

echo
echo "Done: https://github.com/cyberneura/icontuck/releases/tag/v${VERSION}"
echo "Next: copy the version and sha256 from the run summary into"
echo "      Casks/icontuck.rb in the homebrew-tap repo."

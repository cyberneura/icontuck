#!/usr/bin/env bash
# Prints a version number out of the Xcode project, the single source of truth
# for a release. Info.plist carries $(MARKETING_VERSION) and
# $(CURRENT_PROJECT_VERSION), and both scripts/release.sh and the Release
# workflow read the values through here, so the app bundle, the git tag and the
# dmg filename all come from this one place.
#
#   version.sh          -> MARKETING_VERSION       (e.g. 0.1.0)
#   version.sh build    -> CURRENT_PROJECT_VERSION (e.g. 42)
#
# Every occurrence of the setting has to carry the same value. Returning the first
# match instead would let Debug and Release drift apart: release.sh would rewrite
# and re-verify only the configuration it happened to read, and push a release
# commit whose Release build carries a stale version.
#
# Occurrences are collected regardless of how the value is written, and the format
# is checked afterwards. Matching only well-formed values would hide exactly the
# disagreement this is here to catch: Xcode quotes a value such as "1.0.0-beta",
# and a quoted configuration would drop out of the comparison instead of failing
# it.
#
# The setting name is anchored to any character that cannot be part of a setting
# name, so that an unrelated setting ending in the same one (FOO_MARKETING_VERSION)
# is not read as this one. The class has to stay this wide: project.pbxproj is
# currently one settings-per-line file, but Xcode rewrites it into tab-indented
# canonical form the first time it saves the project — which the Build steps in
# README ask you to do — and a narrower anchor would stop matching at that point.
#
# What this does NOT catch is a configuration that omits the setting entirely: it
# contributes no occurrence, so the remaining ones still look unanimous. Detecting
# that would mean parsing the project's configuration list, which is not worth it
# here — a configuration with no value expands $(MARKETING_VERSION) to nothing,
# and the release workflow's bundle version assert fails loudly on the result.
set -euo pipefail

cd "$(dirname "$0")/.."

case "${1:-marketing}" in
  marketing) SETTING=MARKETING_VERSION ;;
  build) SETTING=CURRENT_PROJECT_VERSION ;;
  *)
    echo "Usage: version.sh [marketing|build]" >&2
    exit 1
    ;;
esac

# awk rather than `sed | head -1`: under `set -o pipefail` the closing pipe can
# race sed into a SIGPIPE exit and take the script down with it. The inner loop
# is needed because project.pbxproj puts every setting of a configuration on one
# semicolon-separated line.
VALUES=$(awk -v setting="${SETTING}" '
  {
    line = $0
    while (match(line, "(^|[^A-Za-z0-9_])" setting " = [^;]*;")) {
      field = substr(line, RSTART, RLENGTH)
      sub(/^[^A-Za-z0-9_]/, "", field)
      sub(setting " = ", "", field)
      sub(/;$/, "", field)
      # Xcode quotes a value only when it has to, so the quotes carry no meaning
      # here; stripping them keeps "0.1.0" and 0.1.0 from reading as a mismatch.
      # Only a surrounding pair comes off: gsub would turn 1"2.3 into a value that
      # passes the format checks below.
      if (field ~ /^".*"$/) {
        field = substr(field, 2, length(field) - 2)
      }
      print field
      line = substr(line, RSTART + RLENGTH)
    }
  }' Icontuck.xcodeproj/project.pbxproj | sort -u)

if [ -z "${VALUES}" ]; then
  echo "Error: ${SETTING} not found in Icontuck.xcodeproj/project.pbxproj" >&2
  exit 1
fi
if [ "$(printf '%s\n' "${VALUES}" | wc -l | tr -d ' ')" -ne 1 ]; then
  echo "Error: build configurations disagree on ${SETTING}:" >&2
  printf '  %s\n' ${VALUES} >&2
  exit 1
fi
case "${VALUES}" in
  [0-9]*) ;;
  *)
    echo "Error: ${SETTING} is not a bare number: ${VALUES}" >&2
    exit 1
    ;;
esac
case "${VALUES}" in
  *[!0-9.]* | *..* | *.)
    echo "Error: ${SETTING} is not a bare number: ${VALUES}" >&2
    exit 1
    ;;
esac

printf '%s' "${VALUES}"

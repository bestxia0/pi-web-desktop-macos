#!/usr/bin/env bash
#
# Zero-dependency documentation consistency checks (`make check-docs`).
#
# Guards the three drifts that are otherwise only caught by a human reading a
# diff, all of which have shipped at least once in this repository:
#
#   1. version examples that no longer match the VERSION file (they still said
#      0.7.0 when VERSION was 0.7.1);
#   2. English/Chinese README drift — a screenshot, flag or UserDefaults key
#      present in one file only, which AGENTS.md forbids;
#   3. docs/images holding files nobody references, or the READMEs referencing
#      files that do not exist (a placeholder and a duplicate lived there).
#
# Pure bash + grep + comm: no Node, no Python, no packages.
#
# Exit status: 0 when everything matches, 1 otherwise.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

fail=0
ok() { printf '  \033[32mOK\033[0m   %s\n' "$1"; }
no() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }

VERSION_SEMVER="$(tr -d '[:space:]' < VERSION)"
if [[ ! "$VERSION_SEMVER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  no "VERSION does not hold a bare semver: '${VERSION_SEMVER}'"
  exit 1
fi

echo "Documentation consistency (VERSION = ${VERSION_SEMVER})"

# ---------------------------------------------------------------- version ----
stale=0
while IFS= read -r token; do
  [[ -z "$token" ]] && continue
  if [[ "$token" != "V${VERSION_SEMVER}-"* ]]; then
    no "'$token' does not match VERSION ${VERSION_SEMVER}"
    stale=1
  fi
done < <(grep -Eho 'V[0-9]+\.[0-9]+\.[0-9]+-[0-9]{8}' README.md README.zh-CN.md CHANGELOG.md | sort -u)
((stale == 0)) && ok "every V<semver>-<date> example uses ${VERSION_SEMVER}"

grep -q "^## \[${VERSION_SEMVER}\] " CHANGELOG.md \
  && ok "CHANGELOG has a [${VERSION_SEMVER}] section" \
  || no "CHANGELOG has no [${VERSION_SEMVER}] section"
grep -q "^\[${VERSION_SEMVER}\]: " CHANGELOG.md \
  && ok "CHANGELOG links [${VERSION_SEMVER}] to its release" \
  || no "CHANGELOG is missing the [${VERSION_SEMVER}] link definition"
grep -q "^\[Unreleased\]: .*compare/v${VERSION_SEMVER}\.\.\.HEAD" CHANGELOG.md \
  && ok "[Unreleased] compares from v${VERSION_SEMVER}" \
  || no "[Unreleased] does not compare from v${VERSION_SEMVER}"

# The version table inside each README must quote the current semver.
for file in README.md README.zh-CN.md; do
  section="$(awk '/^#{2,3} (Version|版本)$/ { flag = 1; next } /^#{1,3} / { flag = 0 } flag' "$file")"
  if [[ -z "$section" ]]; then
    no "$file has no 版本/Version section"
    continue
  fi
  bad="$(printf '%s\n' "$section" \
    | grep -Eo '`[0-9]+\.[0-9]+\.[0-9]+`' | tr -d '`' \
    | grep -v "^${VERSION_SEMVER}$" | sort -u || true)"
  if [[ -z "$bad" ]]; then
    ok "$file version table quotes ${VERSION_SEMVER}"
  else
    no "$file version table quotes a stale version: $(printf '%s' "$bad" | tr '\n' ' ')"
  fi
done

# ------------------------------------------------------------ readme pair ----
compare_tokens() {
  local pattern="$1" label="$2" a b
  a="$(grep -Eho "$pattern" README.md | sort -u)"
  b="$(grep -Eho "$pattern" README.zh-CN.md | sort -u)"
  if [[ "$a" == "$b" ]]; then
    ok "$label set is identical in both READMEs"
  else
    no "$label set differs between README.md and README.zh-CN.md"
    comm -3 <(printf '%s\n' "$a") <(printf '%s\n' "$b") | sed 's/^/       /'
  fi
}

compare_tokens '\-\-[a-z0-9-]+' "CLI flag"
compare_tokens 'PiWeb[A-Za-z]+' "UserDefaults key"
compare_tokens 'PI_[A-Z_]+' "environment variable"

img_en="$(grep -Eo 'docs/images/[A-Za-z0-9._-]+' README.md | sort -u)"
img_zh="$(grep -Eo 'docs/images/[A-Za-z0-9._-]+' README.zh-CN.md | sort -u)"
if [[ "$img_en" == "$img_zh" ]]; then
  ok "both READMEs reference the same screenshots"
else
  no "the READMEs reference different screenshots"
  comm -3 <(printf '%s\n' "$img_en") <(printf '%s\n' "$img_zh") | sed 's/^/       /'
fi

# ----------------------------------------------------------------- images ----
missing=0
while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  if [[ ! -f "$ref" ]]; then
    no "README.md references a missing file: $ref"
    missing=1
  fi
done <<< "$img_en"
while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  if [[ ! -f "$ref" ]]; then
    no "README.zh-CN.md references a missing file: $ref"
    missing=1
  fi
done <<< "$img_zh"
((missing == 0)) && ok "every referenced screenshot exists"

unlisted=0
for path in docs/images/*; do
  base="$(basename "$path")"
  [[ "$base" == "README.md" ]] && continue
  if ! grep -q "$base" README.md README.zh-CN.md docs/images/README.md; then
    no "docs/images/$base is referenced nowhere and listed nowhere"
    unlisted=1
  fi
done
((unlisted == 0)) && ok "every docs/images file is used or documented"

echo
if ((fail == 0)); then
  printf '\033[32mDocumentation is consistent\033[0m\n'
  exit 0
fi
printf '\033[31m%d documentation problem(s)\033[0m\n' "$fail"
exit 1

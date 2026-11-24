#!/usr/bin/env bash
# Prints GitHub release notes for a version: its CHANGELOG.md section plus install/upgrade commands.
# Usage: scripts/release-notes.sh 1.2.3   (a leading "v" is fine)
# Fails if CHANGELOG.md has no non-empty section for that version.
set -euo pipefail

VERSION="${1:?usage: release-notes.sh <version>}"
VERSION="${VERSION#v}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="kashmithnisakya/aeris"

section="$(awk -v v="$VERSION" '
  $0 ~ "^## \\[" v "\\]" { found = 1; next }
  found && /^## \[/       { exit }
  found && /^\[[^]]+\]: /  { exit }
  found                    { print }
' "$ROOT/CHANGELOG.md" | sed -e '/./,$!d')"   # drop leading blank lines

if [ -z "$(printf '%s' "$section" | tr -d '[:space:]')" ]; then
  echo "error: CHANGELOG.md has no entry for $VERSION. Add a '## [$VERSION] - YYYY-MM-DD' section first." >&2
  exit 1
fi

prev="$(git -C "$ROOT" describe --tags --abbrev=0 "v$VERSION^" 2>/dev/null || true)"

printf '%s\n\n' "$section"
cat <<NOTES
---

**Install**
\`\`\`bash
brew install --cask kashmithnisakya/tap/aeris
\`\`\`
or \`curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash\`

**Upgrade:** \`brew upgrade aeris\` (Homebrew picks this up within about an hour), or re-run the install script.
NOTES
if [ -n "$prev" ]; then
  printf '\n**Full diff:** https://github.com/%s/compare/%s...v%s\n' "$REPO" "$prev" "$VERSION"
fi

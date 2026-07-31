#!/usr/bin/env bash
# Publish the Overtype Homebrew Cask for the .app bundle to the tap repo.
# Usage: scripts/publish-cask.sh <version> <zip-path>
# Requires the TAP_GITHUB_TOKEN environment variable.
set -euo pipefail

VERSION="${1:?usage: publish-cask.sh <version> <zip-path>}"
ZIP="${2:?usage: publish-cask.sh <version> <zip-path>}"
: "${TAP_GITHUB_TOKEN:?TAP_GITHUB_TOKEN is required}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Pass the token via an auth header rather than embedding it in the remote URL,
# so it never appears in the URL that git prints on failure.
AUTH_HEADER="Authorization: Basic $(printf 'x-access-token:%s' "$TAP_GITHUB_TOKEN" | base64 | tr -d '\n')"
REPO_URL="https://github.com/stn1slv/homebrew-tap.git"
git -c http.extraheader="$AUTH_HEADER" clone --depth 1 "$REPO_URL" "$TMP"

mkdir -p "$TMP/Casks"
sed -e "s/__VERSION__/${VERSION}/g" -e "s/__SHA256__/${SHA}/g" \
	"$ROOT/build/overtype.rb.tmpl" >"$TMP/Casks/overtype.rb"

git -C "$TMP" add Casks/overtype.rb
if git -C "$TMP" diff --cached --quiet; then
	echo "Cask already up to date; nothing to publish."
	exit 0
fi
git -C "$TMP" \
	-c user.name="github-actions[bot]" \
	-c user.email="github-actions[bot]@users.noreply.github.com" \
	commit -m "chore: update overtype cask to ${VERSION}"
git -C "$TMP" -c http.extraheader="$AUTH_HEADER" push origin HEAD
echo "Published overtype cask ${VERSION}"

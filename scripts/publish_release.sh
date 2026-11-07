#!/usr/bin/env bash
set -euo pipefail

# Determine project root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Extract version from pubspec.yaml if not passed as argument
TAG="${1:-}"
if [ -z "$TAG" ]; then
  VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | cut -d'+' -f1 | tr -d '[:space:]')
  TAG="v${VERSION}"
fi

TITLE="${2:-Cadmium $TAG}"
BODY="${3:-Release $TAG of Cadmium with the latest performance and UI improvements.}"

echo "=========================================="
echo "Publishing Release: $TAG"
echo "=========================================="

# 1. Ensure latest release APK is built
APK_SOURCE="build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$APK_SOURCE" ]; then
  echo "Building release APK..."
  flutter build apk --release
fi

TARGET_APK="cadmium-${TAG}.apk"
cp "$APK_SOURCE" "$TARGET_APK"
echo "Prepared $TARGET_APK ($(ls -lh "$TARGET_APK" | awk '{print $5}'))"

# 2. Extract GitHub authentication token from git credential helper
echo "Retrieving GitHub credentials..."
TOKEN=$(printf "protocol=https\nhost=github.com\n" | git credential fill | grep '^password=' | cut -d= -f2 || true)
if [ -z "$TOKEN" ]; then
  echo "Error: GitHub credentials not found via git credential helper."
  exit 1
fi

REPO="dev-o-los/cadmium"

# 3. Update local git tag and force-push to remote
echo "Updating git tag $TAG..."
git tag -fa "$TAG" -m "$TITLE"
git push origin "$TAG" --force

# 4. Check if release already exists on GitHub
RELEASE_ID=$(curl -s -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$REPO/releases/tags/$TAG" | grep '"id":' | head -n 1 | awk '{print $2}' | tr -d ',' || true)

if [ -z "$RELEASE_ID" ] || [ "$RELEASE_ID" = "null" ]; then
  echo "Creating new GitHub release for $TAG..."
  CREATE_RES=$(curl -s -X POST \
    -H "Authorization: token $TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$REPO/releases" \
    -d "{
      \"tag_name\": \"$TAG\",
      \"target_commitish\": \"main\",
      \"name\": \"$TITLE\",
      \"body\": \"$BODY\",
      \"draft\": false,
      \"prerelease\": false
    }")
  RELEASE_ID=$(echo "$CREATE_RES" | grep '"id":' | head -n 1 | awk '{print $2}' | tr -d ',')
else
  echo "Release $TAG already exists (ID: $RELEASE_ID). Updating release details..."
  curl -s -X PATCH \
    -H "Authorization: token $TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$REPO/releases/$RELEASE_ID" \
    -d "{
      \"name\": \"$TITLE\",
      \"body\": \"$BODY\"
    }" > /dev/null
fi

# 5. Delete existing assets with same name if any
EXISTING_ASSETS=$(curl -s -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$REPO/releases/$RELEASE_ID/assets")

for ASSET_NAME in "$TARGET_APK" "app-release.apk"; do
  ASSET_ID=$(echo "$EXISTING_ASSETS" | grep -B 2 "\"name\": \"$ASSET_NAME\"" | grep '"id":' | head -n 1 | awk '{print $2}' | tr -d ',' || true)
  if [ -n "$ASSET_ID" ] && [ "$ASSET_ID" != "null" ]; then
    echo "Removing previous asset $ASSET_NAME (ID: $ASSET_ID)..."
    curl -s -X DELETE \
      -H "Authorization: token $TOKEN" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/$REPO/releases/assets/$ASSET_ID" > /dev/null
  fi
done

# 6. Upload fresh APK assets
echo "Uploading $TARGET_APK to GitHub Releases..."
curl -s -X POST \
  -H "Authorization: token $TOKEN" \
  -H "Content-Type: application/vnd.android.package-archive" \
  --data-binary @"$TARGET_APK" \
  "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=$TARGET_APK" > /dev/null

echo "Uploading app-release.apk..."
curl -s -X POST \
  -H "Authorization: token $TOKEN" \
  -H "Content-Type: application/vnd.android.package-archive" \
  --data-binary @"$APK_SOURCE" \
  "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=app-release.apk" > /dev/null

echo ""
echo "✅ Successfully published to GitHub Releases!"
echo "Release URL: https://github.com/$REPO/releases/tag/$TAG"


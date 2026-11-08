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
# Clean up target APK in root directory on exit
trap 'rm -f "$ROOT_DIR/$TARGET_APK"' EXIT

echo "Prepared $TARGET_APK ($(ls -lh "$TARGET_APK" | awk '{print $5}'))"

# 2. Extract GitHub authentication token
echo "Retrieving GitHub credentials..."
TOKEN="${GITHUB_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  TOKEN=$(printf "protocol=https\nhost=github.com\n" | git credential fill 2>/dev/null | grep '^password=' | cut -d= -f2 || true)
fi

if [ -z "$TOKEN" ]; then
  echo "Error: GitHub credentials not found. Please set GITHUB_TOKEN or configure git credentials."
  exit 1
fi

REPO="dev-o-los/cadmium"

# 3. Update local git tag and force-push to remote
echo "Updating git tag $TAG..."
git tag -fa "$TAG" -m "$TITLE"
git push origin "$TAG" --force

# 4. Check if release already exists on GitHub
echo "Checking existing releases for tag $TAG..."
GET_RELEASE_RES=$(curl -s \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$REPO/releases/tags/$TAG")

RELEASE_ID=$(echo "$GET_RELEASE_RES" | python3 -c "import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('id', ''))
except:
    print('')")

if [ -z "$RELEASE_ID" ] || [ "$RELEASE_ID" = "None" ]; then
  echo "Creating new GitHub release for $TAG..."
  CREATE_RES=$(curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
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
  RELEASE_ID=$(echo "$CREATE_RES" | python3 -c "import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('id', ''))
except:
    print('')")
  
  if [ -z "$RELEASE_ID" ] || [ "$RELEASE_ID" = "None" ]; then
    echo "Error creating release:"
    echo "$CREATE_RES"
    exit 1
  fi
else
  echo "Release $TAG already exists (ID: $RELEASE_ID). Updating release details..."
  curl -s -X PATCH \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$REPO/releases/$RELEASE_ID" \
    -d "{
      \"name\": \"$TITLE\",
      \"body\": \"$BODY\"
    }" > /dev/null
fi

# 5. Delete existing assets with same name if any
EXISTING_ASSETS=$(curl -s \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$REPO/releases/$RELEASE_ID/assets")

ASSET_IDS=$(echo "$EXISTING_ASSETS" | python3 -c "import sys, json
try:
    assets = json.load(sys.stdin)
    if isinstance(assets, list):
        for a in assets:
            if a.get('name') == '$TARGET_APK':
                print(a.get('id'))
except:
    pass")

for ASSET_ID in $ASSET_IDS; do
  if [ -n "$ASSET_ID" ]; then
    echo "Removing previous asset (ID: $ASSET_ID)..."
    curl -s -X DELETE \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/$REPO/releases/assets/$ASSET_ID" > /dev/null
  fi
done

# 6. Upload fresh APK asset
echo "Uploading $TARGET_APK to GitHub Releases..."
UPLOAD_RES=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/vnd.android.package-archive" \
  --data-binary @"$TARGET_APK" \
  "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=$TARGET_APK")

HTTP_CODE=$(echo "$UPLOAD_RES" | tail -n 1)
RESPONSE_BODY=$(echo "$UPLOAD_RES" | sed '$d')

if [ "$HTTP_CODE" -ne 201 ] && [ "$HTTP_CODE" -ne 200 ]; then
  echo "Asset upload failed (HTTP $HTTP_CODE):"
  echo "$RESPONSE_BODY"
  exit 1
fi

echo ""
echo "✅ Successfully published to GitHub Releases!"
echo "Release URL: https://github.com/$REPO/releases/tag/$TAG"
echo "Download URL: https://github.com/$REPO/releases/download/$TAG/$TARGET_APK"



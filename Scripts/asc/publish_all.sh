#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
IPA_PATH="$ROOT_DIR/build/AntigravityRemote.ipa"
ASC_DIR="$ROOT_DIR/Scripts/asc"
VERSION="1.0.0"
BUILD_NUM="13"

echo "=== [1/6] Verifying App Record in App Store Connect (com.liling.AntigravityRemote) ==="
python3 "$ASC_DIR/asc.py" GET "/v1/apps?filter[bundleId]=com.liling.AntigravityRemote"

echo "=== [2/6] Uploading signed IPA ($IPA_PATH) via xcrun altool ==="
ASC_KEY_ID="${ASC_KEY_ID:-$(python3 -c 'import json,os; p=os.path.expanduser("~/.appstoreconnect/config.json"); print(json.load(open(p)).get("key_id","") if os.path.exists(p) else "")')}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-$(python3 -c 'import json,os; p=os.path.expanduser("~/.appstoreconnect/config.json"); print(json.load(open(p)).get("issuer_id","") if os.path.exists(p) else "")')}"
if [[ -z "$ASC_KEY_ID" || -z "$ASC_ISSUER_ID" ]]; then
  echo "Error: Missing ASC_KEY_ID or ASC_ISSUER_ID (set env vars or configure ~/.appstoreconnect/config.json)" >&2
  exit 1
fi
xcrun altool --upload-app \
  -f "$IPA_PATH" \
  -t ios \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"

echo "=== [3/6] Ensuring App Store Version $VERSION & Free Price Schedule ==="
python3 "$ASC_DIR/release.py" create-version "$VERSION"

echo "=== [4/6] Configuring 12-Language Metadata, Privacy URL, Age Rating & Review Notes ==="
python3 "$ASC_DIR/release.py" setup-metadata "$VERSION"

echo "=== [5/6] Uploading 96 App Store Screenshots (12 Locales x iPhone & iPad) ==="
python3 "$ASC_DIR/upload_shots.py" --version "$VERSION"

echo "=== [6/6] Waiting for Build $BUILD_NUM Processing & Submitting for Review ==="
for i in {1..30}; do
  echo "Checking build $BUILD_NUM status (attempt $i/30)..."
  if python3 "$ASC_DIR/release.py" attach-build "$VERSION" --build "$BUILD_NUM"; then
    echo "Build $BUILD_NUM attached! Submitting for App Review..."
    python3 "$ASC_DIR/release.py" submit "$VERSION" --submit
    echo "🎉 Submitted to App Store Review successfully!"
    exit 0
  fi
  sleep 20
done

echo "⚠️ Build $BUILD_NUM is still processing on Apple servers. Run:"
echo "  python3 Scripts/asc/release.py attach-build $VERSION --build $BUILD_NUM && python3 Scripts/asc/release.py submit $VERSION --submit"

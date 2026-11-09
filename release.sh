#!/bin/bash
# ClipSave release script
# Usage: ./release.sh <version>      e.g. ./release.sh 3.7
#
# Builds a Developer ID signed, notarized, stapled DMG, signs it for Sparkle,
# and publishes it into site/ (the Vercel-hosted website) together with the
# new appcast entry. It does NOT commit or push -- test the DMG first, because
# pushing appcast.xml updates every installed copy.
#
# Prerequisites:
#   1. "Developer ID Application" certificate installed in the login Keychain
#   2. Sparkle private key in the login Keychain (generate_keys)
#   3. notarytool credentials stored under the profile named below
#      xcrun notarytool store-credentials "AC_PASSWORD" --apple-id ... --team-id 6U39FF46MG
#   4. Xcode has resolved the Sparkle package (provides sign_update)
#
# Optional: release-notes/<version>.html -- HTML shown in Sparkle's update window.

set -euo pipefail

# Public site root, no trailing slash. Baked into the appcast enclosure URL.
SITE_URL="https://clipsave-mu.vercel.app"
TEAM_ID="6U39FF46MG"
NOTARY_PROFILE="AC_PASSWORD"

if [ -z "${1:-}" ]; then
    echo "Error: provide a version number (e.g. ./release.sh 3.7)"
    exit 1
fi
if [[ "${SITE_URL}" == *REPLACE_ME* ]]; then
    echo "Error: set SITE_URL at the top of release.sh to the Vercel site address first."
    exit 1
fi

VERSION="$1"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/ClipSave-${VERSION}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/ClipSave-${VERSION}"
APP_PATH="${EXPORT_PATH}/ClipSave.app"
NOTARY_ZIP="${BUILD_DIR}/ClipSave-${VERSION}-notary.zip"
DMG_PATH="${BUILD_DIR}/ClipSave-${VERSION}.dmg"
STAGE_DIR="${BUILD_DIR}/dmg-stage-${VERSION}"
SITE_DIR="${PROJECT_DIR}/site"
FEEDS=("${SITE_DIR}/appcast.xml" "${PROJECT_DIR}/appcast.xml")  # new feed + legacy GitHub-hosted feed
DMG_URL="${SITE_URL}/download/ClipSave-${VERSION}.dmg"

cd "${PROJECT_DIR}"

ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "${TEAM_ID}" | head -1 | sed -E 's/^[[:space:]]*[0-9]+\) [0-9A-F]+ "(.*)"$/\1/' || true)
if [ -z "${ID}" ]; then
    echo "Error: no 'Developer ID Application' identity for team ${TEAM_ID} in the Keychain."
    exit 1
fi

SIGN_UPDATE=$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -type f 2>/dev/null | head -1)
if [ -z "${SIGN_UPDATE}" ]; then
    echo "Error: couldn't find Sparkle's sign_update. Open Xcode, let it resolve packages, then retry."
    exit 1
fi

echo "==> Archiving ClipSave ${VERSION}"
mkdir -p "${BUILD_DIR}"
rm -rf "${ARCHIVE_PATH}" "${EXPORT_PATH}" "${NOTARY_ZIP}" "${DMG_PATH}" "${STAGE_DIR}"

xcodebuild -project ClipSave.xcodeproj \
           -scheme ClipSave \
           -configuration Release \
           -archivePath "${ARCHIVE_PATH}" \
           -destination "generic/platform=macOS" \
           DEVELOPMENT_TEAM="${TEAM_ID}" \
           MARKETING_VERSION="${VERSION}" \
           CURRENT_PROJECT_VERSION="${VERSION}" \
           ENABLE_HARDENED_RUNTIME=YES \
           CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
           OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
           archive

echo "==> Exporting with Developer ID"
cat > "${BUILD_DIR}/exportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
           -archivePath "${ARCHIVE_PATH}" \
           -exportPath "${EXPORT_PATH}" \
           -exportOptionsPlist "${BUILD_DIR}/exportOptions.plist"

echo "==> Notarizing the app"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${NOTARY_ZIP}"
xcrun notarytool submit "${NOTARY_ZIP}" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${APP_PATH}"
rm -f "${NOTARY_ZIP}"

echo "==> Building the DMG"
mkdir -p "${STAGE_DIR}"
ditto "${APP_PATH}" "${STAGE_DIR}/ClipSave.app"
ln -s /Applications "${STAGE_DIR}/Applications"
hdiutil create -volname "ClipSave" -srcfolder "${STAGE_DIR}" -ov -format UDZO "${DMG_PATH}" >/dev/null
rm -rf "${STAGE_DIR}"

echo "==> Signing, notarizing and stapling the DMG"
codesign -s "${ID}" --timestamp "${DMG_PATH}"
xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
# Staple BEFORE Sparkle signing: stapling rewrites the file, which would void the signature.
xcrun stapler staple "${DMG_PATH}"
spctl -a -t open --context context:primary-signature -vv "${DMG_PATH}"

echo "==> Signing the DMG for Sparkle"
SIGNATURE_OUTPUT=$("${SIGN_UPDATE}" "${DMG_PATH}")

echo "==> Publishing into site/"
mkdir -p "${SITE_DIR}/download"
find "${SITE_DIR}/download" -name 'ClipSave-*.dmg' -delete
cp "${DMG_PATH}" "${SITE_DIR}/download/"
sed -i '' -E "s#/download/ClipSave-[0-9.]+\.dmg#/download/ClipSave-${VERSION}.dmg#g" "${SITE_DIR}/index.html" "${PROJECT_DIR}/README.md"
sed -i '' -E "s#\(v[0-9.]+, notarized DMG#(v${VERSION}, notarized DMG#" "${PROJECT_DIR}/README.md"
DMG_MB=$(stat -f %z "${DMG_PATH}" | awk '{ printf "%.1f", $1 / 1000000 }')
sed -i '' -E "s#v[0-9.]+ · [0-9.]+ MB#v${VERSION} · ${DMG_MB} MB#g; s#\"softwareVersion\": \"[0-9.]+\"#\"softwareVersion\": \"${VERSION}\"#" "${SITE_DIR}/index.html"

NOTES_FILE="${PROJECT_DIR}/release-notes/${VERSION}.html"
if [ -f "${NOTES_FILE}" ]; then
    NOTES=$(cat "${NOTES_FILE}")
else
    echo "Warning: ${NOTES_FILE} not found -- using placeholder notes."
    NOTES="<h3>What's new in V${VERSION}</h3><ul><li>Describe changes here</li></ul>"
fi

ITEM_FILE=$(mktemp)
cat > "${ITEM_FILE}" <<EOF
        <item>
            <title>Version ${VERSION}</title>
            <sparkle:version>${VERSION}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <pubDate>$(LC_ALL=C date -R)</pubDate>
            <description><![CDATA[
                ${NOTES}
            ]]></description>
            <enclosure
                url="${DMG_URL}"
                ${SIGNATURE_OUTPUT}
                type="application/octet-stream" />
        </item>

EOF

# Newest item goes first; skip a feed that already has this version.
for FEED in "${FEEDS[@]}"; do
    if grep -q "<sparkle:version>${VERSION}</sparkle:version>" "${FEED}"; then
        echo "   ${FEED}: version ${VERSION} already present, skipped"
        continue
    fi
    ITEM_FILE="${ITEM_FILE}" perl -0pi -e '
        BEGIN { open F, "<", $ENV{ITEM_FILE} or die; local $/; $item = <F>; close F; }
        s{([ \t]*)<item>}{$item$1<item>} or s{([ \t]*)</channel>}{$item$1</channel>};
    ' "${FEED}"
    echo "   ${FEED}: added ${VERSION}"
done
rm -f "${ITEM_FILE}"

echo ""
echo "Release ${VERSION} ready."
echo "   DMG:    ${SITE_DIR}/download/ClipSave-${VERSION}.dmg"
echo "   Feeds:  site/appcast.xml (new installs) and appcast.xml (installs before 3.7)"
echo ""
echo "Next steps:"
echo "  1. Install the DMG yourself and check it launches with no Gatekeeper warning."
echo "  2. Review: git diff --stat"
echo "  3. Commit and push -- Vercel publishes site/ and the legacy feed updates via GitHub."
echo "  4. Verify:  curl -s ${SITE_URL}/appcast.xml | grep sparkle:version"
echo "              curl -sI ${DMG_URL}"

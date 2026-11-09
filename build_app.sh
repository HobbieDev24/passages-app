#!/bin/bash
set -euo pipefail

OPEN_APP=false
PUBLIC_RELEASE=false
for OPTION in "$@"; do
    case "$OPTION" in
        --open) OPEN_APP=true ;;
        --release) PUBLIC_RELEASE=true ;;
        --help)
            echo "Usage: ./build_app.sh [--open] [--release]"
            echo "Public releases require PASSAGES_SIGNING_IDENTITY and PASSAGES_NOTARY_PROFILE."
            exit 0 ;;
        *) echo "Unknown option: $OPTION" >&2; exit 1 ;;
    esac
done
if [[ "$PUBLIC_RELEASE" == true && ( -z "${PASSAGES_SIGNING_IDENTITY:-}" || "${PASSAGES_SIGNING_IDENTITY:-}" == "-" || -z "${PASSAGES_NOTARY_PROFILE:-}" ) ]]; then
    echo "A public release requires a Developer ID Application identity and a notarization profile." >&2
    exit 1
fi
if [[ -n "${PASSAGES_NOTARY_PROFILE:-}" && ( -z "${PASSAGES_SIGNING_IDENTITY:-}" || "${PASSAGES_SIGNING_IDENTITY:-}" == "-" ) ]]; then
    echo "Notarization requires a Developer ID Application identity." >&2
    exit 1
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Passages"
VERSION="1.0.15"
BUNDLE_ID="com.passages.highlights"
DIST_DIR="${ROOT}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
DMG_PATH="${DIST_DIR}/${APP_NAME}.dmg"
SCRATCH_ROOT="${PASSAGES_SCRATCH_PATH:-${ROOT}/.build}"
BUILD_SYSTEM="${PASSAGES_BUILD_SYSTEM:-native}"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/passages-release.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
cd "$ROOT"

BINARIES=()
for ARCH in arm64 x86_64; do
    FLAGS=(--build-system "$BUILD_SYSTEM" --scratch-path "${SCRATCH_ROOT}/${ARCH}"
           --triple "${ARCH}-apple-macosx14.0" --disable-index-store --disable-local-rpath
           -c release --product "$APP_NAME")
    echo "▸ Building ${APP_NAME} for ${ARCH}…"
    swift build "${FLAGS[@]}"
    BIN_DIR="$(swift build "${FLAGS[@]}" --show-bin-path)"
    BINARIES+=("${BIN_DIR}/${APP_NAME}")
done

BUILT_APP="${STAGING}/${APP_NAME}.app"
mkdir -p "${BUILT_APP}/Contents/MacOS" "${BUILT_APP}/Contents/Resources"
lipo -create "${BINARIES[@]}" -output "${BUILT_APP}/Contents/MacOS/${APP_NAME}"
strip -S "${BUILT_APP}/Contents/MacOS/${APP_NAME}"
chmod +x "${BUILT_APP}/Contents/MacOS/${APP_NAME}"
cp "${ROOT}/Resources/AppIcon.icns" "${BUILT_APP}/Contents/Resources/AppIcon.icns"
cp "${ROOT}/LICENSE" "${BUILT_APP}/Contents/Resources/LICENSE"

cat > "${BUILT_APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Passages contributors</string>
</dict>
</plist>
PLIST
printf 'APPL????' > "${BUILT_APP}/Contents/PkgInfo"
plutil -lint "${BUILT_APP}/Contents/Info.plist"

if [[ -n "${PASSAGES_SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$PASSAGES_SIGNING_IDENTITY" "$BUILT_APP"
else
    codesign --force --options runtime --sign - "$BUILT_APP"
    echo "▸ Local signature only: downloaded copies may require macOS Open Anyway approval."
fi
codesign --verify --strict --verbose=1 "$BUILT_APP"

if [[ -n "${PASSAGES_NOTARY_PROFILE:-}" ]]; then
    ditto -c -k --keepParent "$BUILT_APP" "${STAGING}/notarization.zip"
    xcrun notarytool submit "${STAGING}/notarization.zip" --keychain-profile "$PASSAGES_NOTARY_PROFILE" --wait
    xcrun stapler staple "$BUILT_APP"
    xcrun stapler validate "$BUILT_APP"
fi

mkdir -p "${STAGING}/disk-image" "$DIST_DIR"
ditto "$BUILT_APP" "${STAGING}/disk-image/${APP_NAME}.app"
ln -s /Applications "${STAGING}/disk-image/Applications"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "${STAGING}/disk-image" \
    -format UDZO "${STAGING}/${APP_NAME}.dmg"
if [[ -n "${PASSAGES_SIGNING_IDENTITY:-}" ]]; then
    codesign --timestamp --sign "$PASSAGES_SIGNING_IDENTITY" "${STAGING}/${APP_NAME}.dmg"
fi
if [[ -n "${PASSAGES_NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "${STAGING}/${APP_NAME}.dmg" --keychain-profile "$PASSAGES_NOTARY_PROFILE" --wait
    xcrun stapler staple "${STAGING}/${APP_NAME}.dmg"
fi

# Publish the artifacts only after packaging succeeds; keep the previous build on failure.
rm -rf "$APP_DIR"
ditto "$BUILT_APP" "$APP_DIR"
mv -f "${STAGING}/${APP_NAME}.dmg" "$DMG_PATH"
shasum -a 256 "$DMG_PATH"
echo "✓ Built ${APP_DIR} and ${DMG_PATH}"
if [[ "$OPEN_APP" == true ]]; then
    open "$APP_DIR"
fi

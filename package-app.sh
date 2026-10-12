#!/bin/bash
# Assembles MacWine.app: the app (SwiftUI, app/) + CLI (macwine) + runtime (Wine, DXVK, MoltenVK).
#
#   ./package-app.sh                 builds $BUILD/app-stage/MacWine.app
#   ./package-app.sh --install       and replaces ~/Applications/MacWine.app (only while no bottle is running)
#
# Variables: MACWINE_BUILD, MACWINE_DEST (runtime source), MACWINE_APP_DIR (install target),
#           MACWINE_DONATION_URL (optional https link for the app's support button).
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
BUILD="${MACWINE_BUILD:-$HOME/macwine-build}"
RUNTIME_SRC="$(cd "${MACWINE_DEST:-$BUILD/runtime}" && pwd -P)"
APP_DIR="${MACWINE_APP_DIR:-$HOME/Applications}"
STAGE="$BUILD/app-stage"
APP="$STAGE/MacWine.app"
BUNDLE_ID="cz.navratil.macwine"
DONATION_URL="${MACWINE_DONATION_URL:-}"
INSTALL=0 RELEASE=0
case "${1:-}" in --install) INSTALL=1 ;; --release) RELEASE=1 ;; esac
# --release: app WITHOUT runtime + separate runtime archive (downloaded by "macwine runtime install").
#   MACWINE_RELEASE_REPO=<owner>/<repo>   GitHub repository for download URLs (required)
RELEASE_REPO="${MACWINE_RELEASE_REPO:-}"
[ "$RELEASE" = 0 ] || [ -n "$RELEASE_REPO" ] || { echo "Set MACWINE_RELEASE_REPO=<owner>/<repo>"; exit 1; }

case "$DONATION_URL" in ""|https://*) ;; *) echo "MACWINE_DONATION_URL must start with https://"; exit 1 ;; esac
[ -x "$RUNTIME_SRC/lib/wine/x86_64-unix/wine" ] || { echo "No runtime in $RUNTIME_SRC (run the build scripts)"; exit 1; }

echo "== Building the app (swift build)"
swift build -c release --package-path "$SRC/app"
BIN="$SRC/app/.build/release/MacWine"
[ -x "$BIN" ] || { echo "Missing $BIN"; exit 1; }

echo "== Helper tools"
MACWINE_DEST="$RUNTIME_SRC" "$SRC/tools/build-tools.sh" >/dev/null

echo "== Assembling $APP"
mkdir -p "$STAGE"
if [ -e "$APP" ]; then mv "$APP" "$STAGE/MacWine.app.prev-$(date +%s)"; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacWine"
# Sparkle (automatic updates) - whole framework incl. symlinks; the app links @executable_path/../Frameworks
SPARKLE_FW="$SRC/app/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[ -d "$SPARKLE_FW" ] || { echo "Missing $SPARKLE_FW (swift build downloads Sparkle)"; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
cp "$SRC/macwine" "$APP/Contents/Resources/macwine"
chmod +x "$APP/Contents/Resources/macwine"
WINE_V="$("$RUNTIME_SRC/lib/wine/x86_64-unix/wine" --version 2>/dev/null || true)"
DXVK_V="$(strings -a "$RUNTIME_SRC/lib/dxvk/x86_64-windows/d3d11.dll" | grep -E '^v[0-9]+\.[0-9]+' | head -1 || true)"
RT_VERSION="wine${WINE_V#wine-}-dxvk${DXVK_V#v}"
# Content fingerprint: a changed runtime gets a new version, so a stale archive is never reused
# and installed copies download the new runtime. (Symlinks are listed by their target.)
RT_FP="$(cd "$RUNTIME_SRC" && { find . -type f ! -path ./lib/macwine/runtime-version -print0 | sort -z | xargs -0 shasum; find . -type l | sort | while read -r l; do echo "$l -> $(readlink "$l")"; done; } | shasum | cut -c1-8)"
RT_VERSION="$RT_VERSION-mvk$(cat "$RUNTIME_SRC/lib/macwine/moltenvk-version" 2>/dev/null || echo 0)-$RT_FP"
if [ "$RELEASE" = 0 ]; then
  # Runtime: APFS clone (cp -c) - takes no extra space
  cp -cR "$RUNTIME_SRC" "$APP/Contents/Resources/runtime"
else
  echo "== Runtime archive $RT_VERSION"
  OUT="$STAGE/release"; mkdir -p "$OUT/rt"
  RT_ARCHIVE="$OUT/macwine-runtime-$RT_VERSION.tar.xz"
  if [ ! -f "$RT_ARCHIVE" ]; then
    cp -cR "$RUNTIME_SRC" "$OUT/rt/runtime"
    echo "$RT_VERSION" > "$OUT/rt/runtime/lib/macwine/runtime-version"
    XZ_OPT="-T0 -6" tar -cJf "$RT_ARCHIVE.part" -C "$OUT/rt" runtime
    mv "$RT_ARCHIVE.part" "$RT_ARCHIVE"
    mv "$OUT/rt/runtime" "$OUT/rt/runtime.done-$(date +%s)"
  fi
  /usr/bin/jq -n --arg v "$RT_VERSION" \
    --arg u "https://github.com/$RELEASE_REPO/releases/download/runtime-$RT_VERSION/$(basename "$RT_ARCHIVE")" \
    --arg h "$(shasum -a 256 "$RT_ARCHIVE" | cut -d' ' -f1)" --argjson s "$(stat -f %z "$RT_ARCHIVE")" \
    '{version: $v, url: $u, sha256: $h, size: $s}' > "$APP/Contents/Resources/runtime.json"
fi

echo "== Icon"
ICONSET="$STAGE/AppIcon.iconset"
mkdir -p "$ICONSET"
swift "$SRC/tools/make-icon.swift" "$STAGE/AppIcon-1024.png" "$STAGE/Logo-full.png" >/dev/null
# Sidebar logo (no background, outlined glass) - 2x resolution for a ~60 pt tall logo
sips -Z 240 "$STAGE/Logo-full.png" --out "$APP/Contents/Resources/Logo.png" >/dev/null
for s in 16 32 128 256 512; do
  sips -z $s $s "$STAGE/AppIcon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$STAGE/AppIcon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Version shown to users (MACWINE_VERSION, e.g. 1.2.0) and build number Sparkle compares (must only grow).
VERSION="${MACWINE_VERSION:-$(cat "$RUNTIME_SRC/lib/macwine/version" 2>/dev/null || echo dev)}"
BUILD_NUMBER="${MACWINE_BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
# Sparkle feed + public EdDSA key - only for releases where both are configured; otherwise updates stay disabled.
#   MACWINE_SPARKLE_PUBLIC_KEY=<base64 from Sparkle generate_keys>  (the private key never leaves the maintainer's Keychain)
SPARKLE_KEYS=""
if [ -n "$RELEASE_REPO" ] && [ -n "${MACWINE_SPARKLE_PUBLIC_KEY:-}" ]; then
  SPARKLE_KEYS="  <key>SUFeedURL</key><string>https://github.com/$RELEASE_REPO/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>$MACWINE_SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>"
fi
# GitHub repository: community ratings (ratings.json on its "ratings" branch, Discussions) and GitHub Sponsors
GITHUB_REPO="${MACWINE_GITHUB_REPO:-${RELEASE_REPO:-mnavratil92-afk/MacWine}}"
[[ "$GITHUB_REPO" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || { echo "MACWINE_GITHUB_REPO must be <owner>/<repo>"; exit 1; }
DONATION_KEY="  <key>MacWineRepo</key><string>$GITHUB_REPO</string>"
if [ -n "$DONATION_URL" ]; then
  DONATION_KEY="$DONATION_KEY
  <key>MacWineDonationURL</key><string>$DONATION_URL</string>"
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>MacWine</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string></array>
  <key>CFBundleDisplayName</key><string>MacWine</string>
  <key>CFBundleExecutable</key><string>MacWine</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Windows program</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Default</string>
      <key>LSItemContentTypes</key><array><string>com.microsoft.windows-executable</string></array>
      <key>CFBundleTypeExtensions</key><array><string>exe</string></array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key><string>Windows Installer</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Default</string>
      <key>LSItemContentTypes</key><array><string>com.microsoft.windows-installer</string></array>
      <key>CFBundleTypeExtensions</key><array><string>msi</string></array>
    </dict>
  </array>
  <key>UTImportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>com.microsoft.windows-installer</string>
      <key>UTTypeDescription</key><string>Windows Installer</string>
      <key>UTTypeConformsTo</key><array><string>public.data</string></array>
      <key>UTTypeTagSpecification</key>
      <dict><key>public.filename-extension</key><array><string>msi</string></array></dict>
    </dict>
  </array>
$DONATION_KEY
$SPARKLE_KEYS
</dict>
</plist>
EOF
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "== Signing (ad hoc)"
# package-runtime.sh already signed the runtime's Mach-O files; this seals the whole bundle.
codesign --force -s - "$APP"
echo "Done: $APP ($(du -sh "$APP" | cut -f1))"
if [ "$RELEASE" = 1 ]; then
  ZIP="$OUT/MacWine-$VERSION.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  echo "Release files in $OUT:"; ls -lh "$ZIP" "$RT_ARCHIVE" | awk '{print "  " $5 "  " $9}'
  exit 0
fi

[ "$INSTALL" = 1 ] || exit 0

echo "== Installing into $APP_DIR"
for b in "$HOME/MacWine/bottles"/*/; do
  [ -d "$b" ] || continue
  if "$APP/Contents/Resources/macwine" settings "$(basename "$b")" 2>/dev/null | grep -q '^running=true'; then
    echo "Bottle $(basename "$b") is running - stop it (macwine kill $(basename "$b")) and run again with --install."
    exit 2
  fi
done
mkdir -p "$APP_DIR"
if [ -e "$APP_DIR/MacWine.app" ]; then
  # The old version is only moved into the build folder (the user may delete it); nothing is deleted.
  mv "$APP_DIR/MacWine.app" "$STAGE/MacWine.app.installed-$(date +%s)"
fi
mv "$APP" "$APP_DIR/MacWine.app"
ln -sfn "$APP_DIR/MacWine.app/Contents/Resources/runtime" "$HOME/MacWine/runtime"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR/MacWine.app"
echo "Installed: $APP_DIR/MacWine.app"
# A running MacWine keeps executing the old code from memory - restart it so the update takes effect
if pgrep -f "$APP_DIR/MacWine.app/Contents/MacOS/MacWine" >/dev/null; then
  pkill -f "$APP_DIR/MacWine.app/Contents/MacOS/MacWine" || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "$APP_DIR/MacWine.app/Contents/MacOS/MacWine" >/dev/null || break; sleep 0.5; done
  open "$APP_DIR/MacWine.app" && echo "MacWine restarted"
fi

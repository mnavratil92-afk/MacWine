#!/bin/bash
# Sestavi MoltenVK ze zdrojoveho archivu (vyzaduje Xcode z App Store).
# Pouziva upraveny SPIRV-Cross z archivu (External/SPIRV-Cross), ostatni zavislosti
# stahne fetchDependencies v revizich z ExternalRevisions.
set -euo pipefail

BUILD="${MACWINE_BUILD:-$HOME/macwine-build}"
SRC="$BUILD/sources/moltenvk"
DEST="${MACWINE_DEST:-${MACWINE_BUILD:-$HOME/macwine-build}/runtime}/lib"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="/opt/homebrew/bin:$PATH"

[ -d "$DEVELOPER_DIR" ] || { echo "Xcode nenalezen v $DEVELOPER_DIR"; exit 1; }

cd "$SRC"
# Xcode 27 podporuje nejstarsi macOS 12.0; projekty maji 10.15/10.13.
find . -name project.pbxproj -not -path './External/*/External/*' -print0 | \
  xargs -0 sed -i '' -E 's/MACOSX_DEPLOYMENT_TARGET = 10\.[0-9]+;/MACOSX_DEPLOYMENT_TARGET = 12.0;/'
# SPIRV-Cross z archivu vybalime zvlast: fetchDependencies External/SPIRV-Cross
# smaze a nahradi odkazem na --spirv-cross-root.
SPVC="$BUILD/spirv-cross-cx"
if [ ! -f "$SPVC/spirv_parser.cpp" ]; then
  mkdir -p "$SPVC"
  tar xzf "$BUILD/wine-sources-26.3.0.tar.gz" -C "$SPVC" --strip-components=4 sources/moltenvk/External/SPIRV-Cross
fi
if [ ! -f "$BUILD/obj/.moltenvk-deps.done" ]; then
  ./fetchDependencies --macos --spirv-cross-root "$SPVC"
  touch "$BUILD/obj/.moltenvk-deps.done"
fi
make macos
mkdir -p "$DEST"
# Prepis podepsane knihovny na miste macOS odmita, proto kopie vedle a prejmenovani.
cp Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib "$DEST/libMoltenVK.dylib.new"
mv -f "$DEST/libMoltenVK.dylib.new" "$DEST/libMoltenVK.dylib"
lipo -info "$DEST/libMoltenVK.dylib"

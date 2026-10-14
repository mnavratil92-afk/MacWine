#!/bin/bash
# Builds MoltenVK from the source archive (needs Xcode from the App Store).
# Uses the adapted SPIRV-Cross from the archive (External/SPIRV-Cross); the other dependencies
# are fetched by fetchDependencies at the revisions in ExternalRevisions.
set -euo pipefail

BUILD="${MACWINE_BUILD:-$HOME/macwine-build}"
SRC="$BUILD/sources/moltenvk"
DEST="${MACWINE_DEST:-${MACWINE_BUILD:-$HOME/macwine-build}/runtime}/lib"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="/opt/homebrew/bin:$PATH"

[ -d "$DEVELOPER_DIR" ] || { echo "Xcode not found in $DEVELOPER_DIR"; exit 1; }

cd "$SRC"
# Xcode 27 supports macOS 12.0 at the oldest; the projects target 10.15/10.13.
find . -name project.pbxproj -not -path './External/*/External/*' -print0 | \
  xargs -0 sed -i '' -E 's/MACOSX_DEPLOYMENT_TARGET = 10\.[0-9]+;/MACOSX_DEPLOYMENT_TARGET = 12.0;/'
# Extract the archive's SPIRV-Cross separately: fetchDependencies deletes External/SPIRV-Cross
# and replaces it with a link to --spirv-cross-root.
SPVC="$BUILD/spirv-cross-cx"
if [ ! -f "$SPVC/spirv_parser.cpp" ]; then
  mkdir -p "$SPVC"
  tar xzf "$BUILD/wine-sources-26.3.0.tar.gz" -C "$SPVC" --strip-components=4 sources/moltenvk/External/SPIRV-Cross
fi
# MacWine's SPIRV-Cross fix (aliased combined image-samplers, needed by DXVK's D3D9 shaders). A newly
# applied patch means the SPIRV-Cross libraries must be rebuilt.
SPVC_PATCH="$(cd "$(dirname "$0")" && pwd)/patches/moltenvk-spirv-cross-alias-sampler.patch"
if [ ! -f "$SPVC/.macwine-alias-sampler" ]; then
  patch -d "$SPVC" -p3 -N < "$SPVC_PATCH"
  touch "$SPVC/.macwine-alias-sampler"
  rm -f "$BUILD/obj/.moltenvk-deps.done"
fi
if [ ! -f "$BUILD/obj/.moltenvk-deps.done" ]; then
  ./fetchDependencies --macos --spirv-cross-root "$SPVC"
  touch "$BUILD/obj/.moltenvk-deps.done"
fi
make macos
mkdir -p "$DEST"
# macOS refuses to overwrite a signed library in place, so copy next to it and rename.
cp Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib "$DEST/libMoltenVK.dylib.new"
mv -f "$DEST/libMoltenVK.dylib.new" "$DEST/libMoltenVK.dylib"
lipo -info "$DEST/libMoltenVK.dylib"

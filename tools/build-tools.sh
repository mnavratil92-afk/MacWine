#!/bin/bash
# Builds MacWine's small native helper tools into runtime/lib/macwine.
set -euo pipefail
cd "$(dirname "$0")"
DEST="${MACWINE_DEST:-${MACWINE_BUILD:-$HOME/macwine-build}/runtime}/lib/macwine"
mkdir -p "$DEST"
clang -O2 -Wall -Wextra -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 exeicon.c -o "$DEST/exeicon"
clang -O2 -Wall -Wextra -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 steamappinfo.c -o "$DEST/steamappinfo"
clang -O2 -Wall -Wextra -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 ubiconfig.c -o "$DEST/ubiconfig"
clang -O2 -Wall -Wextra -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 lnkinfo.c -o "$DEST/lnkinfo"
cp "$DEST/exeicon" ./exeicon 2>/dev/null || true
echo "Tools in $DEST"

# cabextract (needed by winetricks for Microsoft redistributables) - universal binary from the source archive
BUILD="${MACWINE_BUILD:-$HOME/macwine-build}"
if [ -d "$BUILD/sources/cabextract" ]; then
  mkdir -p "$BUILD/obj/cabextract"
  ( cd "$BUILD/obj/cabextract"
    [ -f Makefile ] || CFLAGS="-O2 -arch arm64 -arch x86_64 -mmacosx-version-min=12.0" \
      "$BUILD/sources/cabextract/configure" --disable-dependency-tracking >/dev/null
    make -j8 >/dev/null )
  cp "$BUILD/obj/cabextract/cabextract" "$DEST/cabextract"
fi

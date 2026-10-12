#!/bin/bash
# Sestavi DXVK 1.10.3 (varianta upravena pro MoltenVK, ze zdrojoveho archivu) pro 32 i 64 bitu.
# Bez dxgi.dll (pouziva se dxgi z Wine).
set -euo pipefail

BUILD="${MACWINE_BUILD:-$HOME/macwine-build}"
SRC="$BUILD/sources/dxvk"
DEST="${MACWINE_DEST:-${MACWINE_BUILD:-$HOME/macwine-build}/runtime}/lib/dxvk"
# Prekladac GCC 13 + msvcrt (build-toolchain.sh)
export PATH="$BUILD/toolchain/bin:/opt/homebrew/bin:$PATH"

for arch in 64 32; do
  case $arch in
    64) dir=x86_64-windows ;;
    32) dir=i386-windows ;;
  esac
  OBJ="$BUILD/obj/dxvk$arch"
  if [ ! -f "$OBJ/build.ninja" ]; then
    meson setup "$OBJ" "$SRC" --cross-file "$SRC/build-win$arch.txt" \
      --buildtype release --strip -Denable_dxgi=false -Denable_tests=false \
      -Dcpp_args="['-include','cstdint']"
  fi
  ninja -C "$OBJ"
  mkdir -p "$DEST/$dir"
  find "$OBJ/src" -name 'd3d*.dll' -exec cp {} "$DEST/$dir/" \;
  # meson --strip plati jen pro "meson install"; DLL kopirujeme primo, tak je orizneme sami
  case $arch in 64) strip=x86_64-w64-mingw32-strip ;; 32) strip=i686-w64-mingw32-strip ;; esac
  "$strip" "$DEST/$dir"/d3d*.dll
done
ls -R "$DEST"

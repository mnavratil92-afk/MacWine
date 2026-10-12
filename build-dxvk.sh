#!/bin/bash
# Builds DXVK 1.10.3 (the MoltenVK-adapted variant from the source archive) for 32 and 64 bit.
# Without dxgi.dll (Wine's dxgi is used).
set -euo pipefail

BUILD="${MACWINE_BUILD:-$HOME/macwine-build}"
SRC="$BUILD/sources/dxvk"
DEST="${MACWINE_DEST:-${MACWINE_BUILD:-$HOME/macwine-build}/runtime}/lib/dxvk"
# Compiler: GCC 13 + msvcrt (build-toolchain.sh)
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
  # meson --strip only applies to "meson install"; the DLLs are copied directly, so strip them here
  case $arch in 64) strip=x86_64-w64-mingw32-strip ;; 32) strip=i686-w64-mingw32-strip ;; esac
  "$strip" "$DEST/$dir"/d3d*.dll
done
ls -R "$DEST"

#!/bin/bash
# Zkopiruje x86_64 knihovny (freetype, gnutls, nettle, gmp) do runtime/lib a prepise
# jejich cesty na @loader_path, aby runtime nezaviselo na adresari se sestavenim.
set -euo pipefail

BUILD="${MACWINE_BUILD:-$HOME/macwine-build}"
DEPS="$BUILD/deps-x86_64/lib"
LIB="${MACWINE_DEST:-${MACWINE_BUILD:-$HOME/macwine-build}/runtime}/lib"

mkdir -p "$LIB"
RT="$(dirname "$LIB")"

# 1) Libraries Wine loads by name (dlopen via DYLD_FALLBACK_LIBRARY_PATH): FreeType, GnuTLS stack
for f in "$DEPS"/lib{freetype,gnutls,nettle,hogweed,gmp}*.dylib; do
  [ -L "$f" ] && continue
  cp "$f" "$LIB/"
done
for f in "$DEPS"/lib{freetype,gnutls,nettle,hogweed,gmp}*.dylib; do
  [ -L "$f" ] && ln -sf "$(readlink "$f")" "$LIB/$(basename "$f")"
done

# 2) GStreamer plugins (in-game videos) into lib/gstreamer-1.0
if [ -d "$DEPS/gstreamer-1.0" ]; then
  mkdir -p "$LIB/gstreamer-1.0"
  cp "$DEPS"/gstreamer-1.0/*.dylib "$LIB/gstreamer-1.0/"
fi

# 3) Every Mach-O in the runtime: copy any library it links from the build prefix into lib/ and
#    rewrite the reference relative to the file (@loader_path), so the runtime works on any Mac.
rel_to_lib() { # file -> relative path from its directory to $LIB
  case "$(dirname "$1")" in
    "$LIB") echo "@loader_path" ;;
    "$LIB/gstreamer-1.0") echo "@loader_path/.." ;;
    "$LIB/wine/x86_64-unix") echo "@loader_path/../.." ;;
    "$RT/bin") echo "@loader_path/../lib" ;;
    *) echo "" ;;
  esac
}
changed=1
while [ "$changed" = 1 ]; do
  changed=0
  while IFS= read -r f; do
    file "$f" | grep -q "Mach-O" || continue
    rel="$(rel_to_lib "$f")"; [ -n "$rel" ] || continue
    touched=0
    # build-prefix rpaths (left by the linker) are dropped everywhere
    for rp in $(otool -l "$f" | awk '/LC_RPATH/{r=1} r&&/ path /{print $2; r=0}' | { grep "/macwine-build/" || true; }); do
      install_name_tool -delete_rpath "$rp" "$f" 2>/dev/null && touched=1
    done
    case "$(basename "$f")" in libMoltenVK.dylib) install_name_tool -id "@rpath/libMoltenVK.dylib" "$f" 2>/dev/null && touched=1 ;; esac
    # Wine's unix modules dlopen() libraries by bare name (libgnutls.30.dylib, libfreetype.6.dylib...).
    # dyld resolves those through the caller's LC_RPATH, so point it at runtime/lib - otherwise only
    # DYLD_FALLBACK_LIBRARY_PATH would work, and processes that do not inherit it (Steam restarting
    # itself) end up without GnuTLS: no certificate signature checks, Steam cannot log in.
    if [ "$(dirname "$f")" = "$LIB/wine/x86_64-unix" ] && ! otool -l "$f" | grep -q "path @loader_path/../.. "; then
      install_name_tool -add_rpath "@loader_path/../.." "$f" 2>/dev/null && touched=1
    fi
    deps="$(otool -L "$f" | awk 'NR>1 {print $1}' | { grep "^$DEPS/" || true; })"
    if [ -z "$deps" ]; then [ "$touched" = 0 ] || codesign -f -s - "$f" 2>/dev/null || true; continue; fi
    while IFS= read -r dep; do
      base="$(basename "$dep")"
      if [ ! -e "$LIB/$base" ]; then cp -L "$dep" "$LIB/$base"; changed=1; fi
      install_name_tool -change "$dep" "$rel/$base" "$f" 2>/dev/null
    done <<< "$deps"
    # own id + drop the build-prefix rpath
    case "$f" in *.dylib) install_name_tool -id "@rpath/$(basename "$f")" "$f" 2>/dev/null || true ;; esac
    codesign -f -s - "$f" 2>/dev/null || true
  done < <(find "$LIB" "$RT/bin" -type f \( -name '*.dylib' -o -name '*.so' -o -perm +111 \) -not -path '*/x86_64-windows/*' -not -path '*/i386-windows/*' -not -path '*/dxvk/*')
done
echo "Knihovny v $LIB:"; ls "$LIB" | grep -v '^wine$\|^dxvk$\|^macwine$' | tr '\n' ' '; echo

# Verze SDK v binarkach nastavena na macOS SDK 15.1. macOS podle ni zapina
# "linked-on-or-after" chovani AppKitu/Metalu/CAMetalLayer; se SDK 27 hry zamrzaly pri present.
# Meni se jen udaj o SDK, ne kod ani minimalni verze macOS.
RT="$(dirname "$LIB")"
SDK_AS=15.1
for f in "$RT/lib/wine/x86_64-unix/wine" "$RT/bin/wineserver" "$RT"/lib/wine/x86_64-unix/*.so "$LIB/libMoltenVK.dylib"; do
  [ -f "$f" ] && [ ! -L "$f" ] || continue
  for arch in $(lipo -archs "$f"); do
    minos=$(otool -arch "$arch" -l "$f" | awk '/LC_BUILD_VERSION/{b=1} b&&/minos/{print $2; exit}')
    [ -n "$minos" ] || continue
    xcrun vtool -arch "$arch" -set-build-version macos "$minos" "$SDK_AS" -replace -output "$f.vtool" "$f" >/dev/null
    mv -f "$f.vtool" "$f"
  done
  codesign -f -s - "$f" 2>/dev/null
done
echo "Verze SDK nastavena na $SDK_AS"

# Verze soucasti pro "macwine version"
mkdir -p "$RT/lib/macwine"
H="$BUILD/sources/moltenvk/MoltenVK/MoltenVK/API/mvk_private_api.h"
[ -f "$H" ] || H="$BUILD/sources/moltenvk/MoltenVK/MoltenVK/API/vk_mvk_moltenvk.h"
awk '/#define MVK_VERSION_MAJOR/{a=$3} /#define MVK_VERSION_MINOR/{b=$3} /#define MVK_VERSION_PATCH/{c=$3} END{if(a!="") print a"."b"."c}' "$H" > "$RT/lib/macwine/moltenvk-version"
# Verzi z gitu jen pokud je MacWine vlastni repozitar (ne podslozka jineho projektu)
SRCDIR="$(cd "$(dirname "$0")" && pwd)"
if [ "$(git -C "$SRCDIR" rev-parse --show-toplevel 2>/dev/null)" = "$SRCDIR" ]; then
  git -C "$SRCDIR" describe --tags --always --dirty > "$RT/lib/macwine/version"
else
  echo dev > "$RT/lib/macwine/version"
fi

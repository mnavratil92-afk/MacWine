#!/bin/bash
# Sestavi Wine 11 ze zdrojoveho archivu jako x86_64 (bezi pod Rosettou, WoW64).
# Na macOS 27 uz nastroje Xcode nebezi pod Rosettou, proto se kompiluje krizove z arm64:
#  1) nativni nastroje Wine (winebuild, widl, ...) pro arm64
#  2) samotne Wine pro x86_64 s pouzitim techto nastroju
set -euo pipefail

BUILD="${MACWINE_BUILD:-$HOME/macwine-build}"
SRC="$BUILD/sources/wine"
DEPS="$BUILD/deps-x86_64"
TOOLS="$BUILD/obj/wine-tools"
OBJ="$BUILD/obj/wine"
DEST="${MACWINE_DEST:-${MACWINE_BUILD:-$HOME/macwine-build}/runtime}"
JOBS="$(sysctl -n hw.ncpu)"

# Prekladac pro Windows cast: GCC 13 (build-toolchain.sh)
export PATH="$BUILD/toolchain/bin:/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:/opt/homebrew/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=11.0

# 1) Nativni nastroje
mkdir -p "$TOOLS"
if [ ! -f "$TOOLS/tools/sfnt2fon/sfnt2fon" ] || [ ! -f "$TOOLS/.freetype" ]; then
  echo "== Nativni nastroje Wine"
  cd "$TOOLS"
  export PATH="$PATH:/opt/homebrew/opt/llvm/bin:/opt/homebrew/opt/lld/bin"
  [ -f Makefile ] || "$SRC/configure" --without-gnutls \
    --without-x --without-vulkan --without-opencl --disable-tests
  make -j"$JOBS" __tooldeps__ tools/sfnt2fon/sfnt2fon && touch "$TOOLS/.freetype"
fi
# wrc/wmc hledaji locale.nls vedle nastroju; pri sestaveni mimo zdroje tam neni.
ln -sf "$SRC/nls/locale.nls" "$TOOLS/nls/locale.nls"

# 2) Wine pro x86_64
# Configure potrebuje libMoltenVK jen k overeni; Wine si ji za behu nacita samo (dlopen).
# Proto se MoltenVK sestavuje pred Wine (build-moltenvk.sh).
STUB="$BUILD/configure-stub"
mkdir -p "$STUB"
MVK="${MOLTENVK_DYLIB:-$DEST/lib/libMoltenVK.dylib}"  # sem instaluje build-moltenvk.sh
[ -f "$MVK" ] || { echo "Chybi $MVK - nejdriv spust build-moltenvk.sh"; exit 1; }
ln -sf "$MVK" "$STUB/libMoltenVK.dylib"

mkdir -p "$OBJ"
cd "$OBJ"
if [ ! -f Makefile ]; then
  echo "== Konfigurace Wine x86_64"
  CC="clang -arch x86_64" CXX="clang++ -arch x86_64" \
  CFLAGS="-O2 -I$DEPS/include" CROSSCFLAGS="-O2 -std=gnu17" \
  LDFLAGS="-L$DEPS/lib -L$STUB -Wl,-rpath,$DEPS/lib" \
  PKG_CONFIG_PATH="$DEPS/lib/pkgconfig" PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig" \
  FREETYPE_CFLAGS="-I$DEPS/include/freetype2" FREETYPE_LIBS="-L$DEPS/lib -lfreetype" \
  GNUTLS_CFLAGS="-I$DEPS/include" GNUTLS_LIBS="-L$DEPS/lib -lgnutls" \
  GSTREAMER_CFLAGS="$(PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig" pkg-config --cflags gstreamer-1.0 gstreamer-video-1.0 gstreamer-audio-1.0 gstreamer-tag-1.0)" \
  GSTREAMER_LIBS="$(PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig" pkg-config --libs gstreamer-1.0 gstreamer-video-1.0 gstreamer-audio-1.0 gstreamer-tag-1.0)" \
  "$SRC/configure" --host=x86_64-apple-darwin --prefix="$DEST" \
    --with-wine-tools="$TOOLS" \
    --enable-archs=i386,x86_64 \
    --disable-tests \
    --without-x --without-wayland --without-oss --without-alsa --without-pulse \
    --without-capi --without-cups --without-sane --without-gphoto --without-v4l2 \
    --without-krb5 --without-netapi --without-pcap --without-usb --without-udev \
    --with-gstreamer --without-sdl --without-dbus --without-inotify \
    --with-freetype --with-gnutls --with-vulkan --with-opencl --with-coreaudio
fi
[ "${CONFIGURE_ONLY:-}" = 1 ] && exit 0
make -j"$JOBS"
make install
echo "Wine nainstalovano do $DEST"

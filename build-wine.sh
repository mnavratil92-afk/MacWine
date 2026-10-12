#!/bin/bash
# Builds Wine 11 from the source archive as x86_64 (runs under Rosetta, WoW64).
# On macOS 27 the Xcode tools no longer run under Rosetta, so Wine is cross-compiled from arm64:
#  1) native Wine build tools (winebuild, widl, ...) for arm64
#  2) Wine itself for x86_64, using those tools
set -euo pipefail

BUILD="${MACWINE_BUILD:-$HOME/macwine-build}"
SRC="$BUILD/sources/wine"
DEPS="$BUILD/deps-x86_64"
TOOLS="$BUILD/obj/wine-tools"
OBJ="$BUILD/obj/wine"
DEST="${MACWINE_DEST:-${MACWINE_BUILD:-$HOME/macwine-build}/runtime}"
JOBS="$(sysctl -n hw.ncpu)"

# Compiler for the Windows side: GCC 13 (build-toolchain.sh)
export PATH="$BUILD/toolchain/bin:/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:/opt/homebrew/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=11.0

# 1) Native tools
mkdir -p "$TOOLS"
if [ ! -f "$TOOLS/tools/sfnt2fon/sfnt2fon" ] || [ ! -f "$TOOLS/.freetype" ]; then
  echo "== Native Wine tools"
  cd "$TOOLS"
  export PATH="$PATH:/opt/homebrew/opt/llvm/bin:/opt/homebrew/opt/lld/bin"
  [ -f Makefile ] || "$SRC/configure" --without-gnutls \
    --without-x --without-vulkan --without-opencl --disable-tests
  make -j"$JOBS" __tooldeps__ tools/sfnt2fon/sfnt2fon && touch "$TOOLS/.freetype"
fi
# wrc/wmc look for locale.nls next to the tools; in an out-of-tree build it is not there.
ln -sf "$SRC/nls/locale.nls" "$TOOLS/nls/locale.nls"

# 2) Wine for x86_64
# configure only needs libMoltenVK for its checks; Wine loads it at run time (dlopen).
# That is why MoltenVK is built before Wine (build-moltenvk.sh).
STUB="$BUILD/configure-stub"
mkdir -p "$STUB"
MVK="${MOLTENVK_DYLIB:-$DEST/lib/libMoltenVK.dylib}"  # installed here by build-moltenvk.sh
[ -f "$MVK" ] || { echo "Missing $MVK - run build-moltenvk.sh first"; exit 1; }
ln -sf "$MVK" "$STUB/libMoltenVK.dylib"

mkdir -p "$OBJ"
cd "$OBJ"
if [ ! -f Makefile ]; then
  echo "== Configuring Wine x86_64"
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
echo "Wine installed into $DEST"

#!/bin/bash
# Builds the x86_64 libraries (FreeType, GMP, Nettle, GnuTLS) for Wine running under Rosetta.
set -euo pipefail

BUILD="${MACWINE_BUILD:-$HOME/macwine-build}"
SRC="$BUILD/sources"
PREFIX="$BUILD/deps-x86_64"
JOBS="$(sysctl -n hw.ncpu)"

export CC="clang -arch x86_64"
export CXX="clang++ -arch x86_64"
export CFLAGS="-O2 -mmacosx-version-min=11.0"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-L$PREFIX/lib -mmacosx-version-min=11.0"
export CPPFLAGS="-I$PREFIX/include"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
HOST="--host=x86_64-apple-darwin"

mkdir -p "$PREFIX" "$BUILD/obj"

build() { # name source_dir [configure arguments...]
  local name="$1" dir="$2"; shift 2
  if [ -f "$BUILD/obj/.$name.done" ]; then echo "== $name already built"; return; fi
  echo "== Building $name"
  rm -rf "$BUILD/obj/$name" && cp -Rp "$dir" "$BUILD/obj/$name" && cd "$BUILD/obj/$name"
  [ -x configure ] || autoreconf -fi
  ./configure $HOST --prefix="$PREFIX" "$@"
  make -j"$JOBS"
  make install
  touch "$BUILD/obj/.$name.done"
}

if [ ! -f "$BUILD/obj/.freetype.done" ]; then
  echo "== Building freetype"
  rm -rf "$BUILD/obj/freetype" && mkdir -p "$BUILD/obj/freetype"
  cmake -S "$SRC/freetype" -B "$BUILD/obj/freetype" -G Ninja -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON -DCMAKE_INSTALL_NAME_DIR="$PREFIX/lib" \
    -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_PNG=ON -DFT_DISABLE_BROTLI=ON -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_ZLIB=ON
  cmake --build "$BUILD/obj/freetype" && cmake --install "$BUILD/obj/freetype"
  touch "$BUILD/obj/.freetype.done"
fi
build gmp      "$SRC/gnutls/gmp" --enable-shared --disable-static
# The archive's Nettle sources lack Makefile.in; use the official release of the same version.
if [ ! -d "$BUILD/upstream/nettle-3.10" ]; then
  mkdir -p "$BUILD/upstream"
  curl -sfL https://ftp.gnu.org/gnu/nettle/nettle-3.10.tar.gz | tar xz -C "$BUILD/upstream"
fi
build nettle   "$BUILD/upstream/nettle-3.10" --enable-shared --disable-static --disable-documentation --disable-openssl
build gnutls   "$SRC/gnutls/gnutls" --enable-shared --disable-static --with-included-libtasn1 \
  --with-included-unistring --without-p11-kit --without-brotli --without-zstd --without-idn \
  --disable-doc --disable-tests --disable-tools --disable-cxx --disable-guile --disable-gost \
  NETTLE_LIBS="-lnettle" HOGWEED_LIBS="-lhogweed -lgmp" NETTLE_CFLAGS="-I$PREFIX/include" HOGWEED_CFLAGS="-I$PREFIX/include"

echo "Done: $PREFIX"

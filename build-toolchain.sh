#!/bin/bash
# Builds the mingw-w64 cross compiler for the Windows side of Wine and DXVK:
# GCC 13 + binutils 2.41, msvcrt CRT, POSIX threads.
# Newer GCC (15/16) compiles Wine and DXVK differently (C23, optimizations) and games then freeze or stutter.
set -euo pipefail

BUILD="${MACWINE_BUILD:-$HOME/macwine-build}"
PREFIX="$BUILD/toolchain"
SRC="$BUILD/toolchain-src"
OBJ="$BUILD/obj/toolchain"
JOBS="$(sysctl -n hw.ncpu)"
BINUTILS=2.41 GCC=13.4.0 MINGW=11.0.1  # GCC 13.2 does not build with Xcode 27's libc++; 13.4 = same series with fixes
BREW=/opt/homebrew/opt

export PATH="$PREFIX/bin:/opt/homebrew/bin:$PATH"
mkdir -p "$SRC" "$OBJ" "$PREFIX"

fetch() { # url
  local f="$SRC/$(basename "$1")"
  [ -f "$f" ] || curl -fL -o "$f" "$1"
  tar xf "$f" -C "$SRC"
}
[ -d "$SRC/binutils-$BINUTILS" ] || fetch "https://ftp.gnu.org/gnu/binutils/binutils-$BINUTILS.tar.xz"
[ -d "$SRC/gcc-$GCC" ] || fetch "https://ftp.gnu.org/gnu/gcc/gcc-$GCC/gcc-$GCC.tar.xz"
[ -d "$SRC/mingw-w64-v$MINGW" ] || fetch "https://downloads.sourceforge.net/project/mingw-w64/mingw-w64/mingw-w64-release/mingw-w64-v$MINGW.tar.bz2"

step() { # name command...
  local name="$1"; shift
  if [ -f "$OBJ/.$name.done" ]; then echo "== $name already built"; return; fi
  echo "== $name"
  "$@"
  touch "$OBJ/.$name.done"
}

for T in x86_64-w64-mingw32 i686-w64-mingw32; do
  case $T in
    x86_64*) CRTFLAGS="--disable-lib32 --enable-lib64" ;;
    i686*)   CRTFLAGS="--enable-lib32 --disable-lib64" ;;
  esac

  binutils() {
    mkdir -p "$OBJ/binutils-$T" && cd "$OBJ/binutils-$T"
    "$SRC/binutils-$BINUTILS/configure" --target=$T --prefix="$PREFIX" \
      --disable-multilib --disable-nls --disable-werror --with-sysroot="$PREFIX/$T" --with-system-zlib
    make -j"$JOBS" && make install
  }
  headers() {
    mkdir -p "$OBJ/headers-$T" && cd "$OBJ/headers-$T"
    "$SRC/mingw-w64-v$MINGW/mingw-w64-headers/configure" --host=$T --prefix="$PREFIX/$T" \
      --with-default-msvcrt=msvcrt
    make install
    ln -sfn . "$PREFIX/$T/mingw"  # GCC looks for headers in <sysroot>/mingw
  }
  gcc1() {
    mkdir -p "$OBJ/gcc-$T" && cd "$OBJ/gcc-$T"
    "$SRC/gcc-$GCC/configure" --target=$T --prefix="$PREFIX" --with-sysroot="$PREFIX/$T" \
      --enable-languages=c,c++ --disable-multilib --disable-nls --enable-threads=posix \
      --disable-libstdcxx-pch --disable-werror --enable-lto --with-system-zlib \
      --with-gmp=$BREW/gmp --with-mpfr=$BREW/mpfr --with-mpc=$BREW/libmpc --with-isl=$BREW/isl
    make -j"$JOBS" all-gcc && make install-gcc
  }
  crt() {
    mkdir -p "$OBJ/crt-$T" && cd "$OBJ/crt-$T"
    "$SRC/mingw-w64-v$MINGW/mingw-w64-crt/configure" --host=$T --prefix="$PREFIX/$T" \
      --with-sysroot="$PREFIX/$T" --with-default-msvcrt=msvcrt $CRTFLAGS
    make -j"$JOBS" && make install
  }
  pthreads() {
    mkdir -p "$OBJ/winpthreads-$T" && cd "$OBJ/winpthreads-$T"
    "$SRC/mingw-w64-v$MINGW/mingw-w64-libraries/winpthreads/configure" --host=$T --prefix="$PREFIX/$T"
    make -j"$JOBS" && make install
  }
  gcc2() {
    cd "$OBJ/gcc-$T"
    make -j"$JOBS" && make install
  }
  step binutils-$T binutils
  step headers-$T headers
  step gcc1-$T gcc1
  step crt-$T crt
  step winpthreads-$T pthreads
  step gcc2-$T gcc2
done

"$PREFIX/bin/x86_64-w64-mingw32-gcc" --version | head -1
"$PREFIX/bin/i686-w64-mingw32-gcc" --version | head -1

#!/bin/bash
# Builds a minimal x86_64 GStreamer (+GLib) for Wine's winegstreamer: in-game videos (MP4/H.264 via the
# Mac's hardware decoder VideoToolbox = "applemedia" plugin, AVI, ASF/WMV container, WAV, audio conversion).
set -euo pipefail

BUILD="${MACWINE_BUILD:-$HOME/macwine-build}"
SRC="$BUILD/sources/gstreamer"
OBJ="$BUILD/obj/gstreamer"
PREFIX="$BUILD/deps-x86_64"
export PATH="/opt/homebrew/bin:$PATH"

CROSS="$BUILD/obj/meson-x86_64-darwin.txt"
# GLib 2.78's code generators need distutils (removed in Python 3.12) - use the system Python 3.9
NATIVE="$BUILD/obj/meson-native-python.txt"
printf "[binaries]\npython = '/usr/bin/python3'\npython3 = '/usr/bin/python3'\nglib-mkenums = '%s'\nglib-genmarshal = '%s'\n" \
  "$PREFIX/bin/glib-mkenums" "$PREFIX/bin/glib-genmarshal" > "$NATIVE"
cat > "$CROSS" <<EOF
[binaries]
c = ['clang', '-arch', 'x86_64', '-mmacosx-version-min=11.0']
cpp = ['clang++', '-arch', 'x86_64', '-mmacosx-version-min=11.0']
objc = ['clang', '-arch', 'x86_64', '-mmacosx-version-min=11.0']
objcpp = ['clang++', '-arch', 'x86_64', '-mmacosx-version-min=11.0']
ar = 'ar'
strip = 'strip'
pkg-config = 'pkg-config'
python = '/usr/bin/python3'
python3 = '/usr/bin/python3'
glib-mkenums = '$PREFIX/bin/glib-mkenums'
glib-genmarshal = '$PREFIX/bin/glib-genmarshal'

[properties]
pkg_config_libdir = '$PREFIX/lib/pkgconfig'

[host_machine]
system = 'darwin'
subsystem = 'macos'
kernel = 'xnu'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

# GLib first, standalone from the source archive (its own wraps: proxy-libintl, libffi, pcre2)
GLIB_OBJ="$BUILD/obj/glib"
# The archive's glib has an empty gvdb submodule; use the official 2.78.3 release (gstreamer's glib.wrap)
GLIB_SRC="$(ls -d "$SRC"/subprojects/glib-2.* 2>/dev/null | head -1)"
if [ -z "$GLIB_SRC" ]; then (cd "$SRC" && meson subprojects download glib); GLIB_SRC="$(ls -d "$SRC"/subprojects/glib-2.* | head -1)"; fi
if [ ! -f "$PREFIX/lib/pkgconfig/glib-2.0.pc" ]; then
  [ -f "$GLIB_OBJ/build.ninja" ] || meson setup "$GLIB_OBJ" "$GLIB_SRC" --cross-file "$CROSS" --native-file "$NATIVE" \
    --prefix="$PREFIX" --buildtype=release --default-library=shared \
    --force-fallback-for=proxy-libintl,libffi,pcre2 -Dtests=false -Dnls=disabled
  ninja -C "$GLIB_OBJ"
  ninja -C "$GLIB_OBJ" install
fi

if [ ! -f "$OBJ/build.ninja" ]; then
  PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" meson setup "$OBJ" "$SRC" --cross-file "$CROSS" --native-file "$NATIVE" \
    --prefix="$PREFIX" --buildtype=release --default-library=shared --wrap-mode=default \
    -Dauto_features=disabled -Dgpl=disabled -Dlibav=disabled -Dugly=enabled -Dgst-plugins-ugly:asfdemux=enabled -Drs=disabled \
    -Dbase=enabled -Dgood=enabled -Dbad=enabled -Dtools=disabled -Dtests=disabled -Dexamples=disabled \
    -Dintrospection=disabled -Ddoc=disabled -Dpython=disabled -Ddevtools=disabled -Dges=disabled \
    -Drtsp_server=disabled -Dvaapi=disabled -Dsharp=disabled -Dqt5=disabled -Dqt6=disabled \
    -Dgstreamer:check=enabled -Dgstreamer:tools=disabled -Dgstreamer:ptp-helper=disabled \
    -Dglib:tests=false \
    -Dgst-plugins-base:app=enabled -Dgst-plugins-base:audioconvert=enabled \
    -Dgst-plugins-base:audioresample=enabled -Dgst-plugins-base:playback=enabled \
    -Dgst-plugins-base:typefind=enabled -Dgst-plugins-base:videoconvertscale=enabled \
    -Dgst-plugins-base:gl=enabled -Dgst-plugins-base:gl_api=opengl -Dgst-plugins-base:gl_platform=cgl \
    -Dgst-plugins-base:gl_winsys=cocoa -Dgst-plugins-base:gl-graphene=disabled \
    -Dgst-plugins-base:gl-jpeg=disabled -Dgst-plugins-base:gl-png=disabled \
    -Dgst-plugins-good:isomp4=enabled -Dgst-plugins-good:avi=enabled -Dgst-plugins-good:wavparse=enabled \
    -Dgst-plugins-good:audioparsers=enabled -Dgst-plugins-good:id3demux=enabled \
    -Dgst-plugins-good:deinterlace=enabled -Dgst-plugins-good:videofilter=enabled \
    -Dgst-plugins-bad:applemedia=enabled -Dgst-plugins-bad:videoparsers=enabled -Dgst-plugins-bad:gl=enabled \
    -Dgst-plugins-bad:asfmux=disabled
fi
ninja -C "$OBJ"
ninja -C "$OBJ" install
ls "$PREFIX/lib/gstreamer-1.0" | tr '\n' ' '; echo

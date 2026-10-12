#!/bin/bash
# Prepares a new build folder; never overwrites an existing build.
set -euo pipefail
export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCHIVE_NAME=crossover-sources-26.3.0.tar.gz
URL="https://media.codeweavers.com/pub/crossover/source/$ARCHIVE_NAME"
# Checksum of the archive used to develop MacWine (not a publisher signature).
EXPECTED_SHA256=ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872
usage() {
  cat <<'HELP'
Usage: ./prepare-sources.sh NEW_BUILD_FOLDER [LOCAL_ARCHIVE]
Prepares sources/ and the archive for build-*.sh. The target must not exist.
Without a local archive it downloads the Wine 26.3.0 source archive published by CodeWeavers.
On failure an empty target folder may remain; existing data is never changed.
HELP
}
die() { echo "prepare-sources: $*" >&2; exit 1; }
if [ "${1:-}" = --help ] || [ "${1:-}" = -h ]; then usage; exit 0; fi
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { usage >&2; exit 2; }
for tool in tar patch shasum mktemp; do command -v "$tool" >/dev/null || die "missing $tool"; done
archive="${2:-}"
if [ -n "$archive" ]; then
  [ -f "$archive" ] || die "archive does not exist: $archive"
  archive="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"
else
  command -v curl >/dev/null || die "missing curl"
fi
# mkdir without -p atomically refuses an existing (even empty) folder or symlink.
mkdir -- "$1" || die "the target must be a new folder inside an existing one: $1"
build="$(cd "$1" && pwd)"
stage="$(mktemp -d "$build/.prepare.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [ -n "$archive" ]; then
  cp "$archive" "$stage/$ARCHIVE_NAME"
else
  curl --fail --location --retry 3 --output "$stage/$ARCHIVE_NAME" "$URL"
fi
actual="$(shasum -a 256 "$stage/$ARCHIVE_NAME" | awk '{print $1}')"
[ "$actual" = "$EXPECTED_SHA256" ] || die "archive SHA-256 mismatch; sources were not extracted"
tar xzf "$stage/$ARCHIVE_NAME" -C "$stage"
for component in wine dxvk moltenvk freetype gnutls; do
  [ -d "$stage/sources/$component" ] || die "the archive has no sources/$component"
done
{
  printf 'Wine source archive 26.3.0 (CodeWeavers)\nURL: %s\nSHA256: %s\n\nPatches (in order of application, SHA256):\n' "$URL" "$actual"
} > "$stage/prepare-sources.manifest"
shopt -s nullglob
patches=("$SCRIPT_DIR"/patches/*.patch)
[ "${#patches[@]}" -gt 0 ] || die "no patches in $SCRIPT_DIR/patches"
for patch_file in "${patches[@]}"; do
  name="$(basename "$patch_file")"
  case "$name" in
    wine-*) component=wine ;;
    dxvk-*) component=dxvk ;;
    moltenvk-*) component=moltenvk ;;
    *) die "unknown patch prefix: $name" ;;
  esac
  echo "== $name -> sources/$component"
  patch -d "$stage/sources/$component" -p1 --batch --forward --fuzz=0 < "$patch_file"
  digest="$(shasum -a 256 "$patch_file" | awk '{print $1}')"
  printf '%s  %s\n' "$digest" "$name" >> "$stage/prepare-sources.manifest"
done
mv "$stage/sources" "$build/sources"
mv "$stage/$ARCHIVE_NAME" "$stage/prepare-sources.manifest" "$build/"
echo "Done: $build"
echo "Set MACWINE_BUILD to this folder for the build scripts."

#!/bin/bash
# Pripravi novy build adresar; existujici sestaveni nikdy neprepisuje.
set -euo pipefail
export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCHIVE_NAME=crossover-sources-26.3.0.tar.gz
URL="https://media.codeweavers.com/pub/crossover/source/$ARCHIVE_NAME"
# Otisk archivu pouziteho pri vyvoji MacWine, nikoli podpis vydavatele.
EXPECTED_SHA256=ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872
usage() {
  cat <<'HELP'
Pouziti: ./prepare-sources.sh NOVY_BUILD_ADRESAR [LOKALNI_ARCHIV]
Pripravi sources/ a archiv pro build-*.sh. Cil nesmi existovat.
Bez lokalniho archivu stahne CrossOver sources 26.3.0 od CodeWeavers.
Pri chybe muze zustat prazdny cilovy adresar; existujici data nemeni.
HELP
}
die() { echo "prepare-sources: $*" >&2; exit 1; }
if [ "${1:-}" = --help ] || [ "${1:-}" = -h ]; then usage; exit 0; fi
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { usage >&2; exit 2; }
for tool in tar patch shasum mktemp; do command -v "$tool" >/dev/null || die "chybi $tool"; done
archive="${2:-}"
if [ -n "$archive" ]; then
  [ -f "$archive" ] || die "archiv neexistuje: $archive"
  archive="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"
else
  command -v curl >/dev/null || die "chybi curl"
fi
# mkdir bez -p atomicky odmitne i existujici prazdny adresar nebo symlink.
mkdir -- "$1" || die "cil musi byt novy adresar s existujicim rodicem: $1"
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
[ "$actual" = "$EXPECTED_SHA256" ] || die "SHA-256 archivu nesouhlasi; zdroje nebyly rozbaleny"
tar xzf "$stage/$ARCHIVE_NAME" -C "$stage"
for component in wine dxvk moltenvk freetype gnutls; do
  [ -d "$stage/sources/$component" ] || die "v archivu chybi sources/$component"
done
{
  printf 'CrossOver sources 26.3.0\nURL: %s\nSHA256: %s\n\nPatche (poradi aplikace a SHA256):\n' "$URL" "$actual"
} > "$stage/prepare-sources.manifest"
shopt -s nullglob
patches=("$SCRIPT_DIR"/patches/*.patch)
[ "${#patches[@]}" -gt 0 ] || die "zadne patche v $SCRIPT_DIR/patches"
for patch_file in "${patches[@]}"; do
  name="$(basename "$patch_file")"
  case "$name" in
    wine-*) component=wine ;;
    dxvk-*) component=dxvk ;;
    moltenvk-*) component=moltenvk ;;
    *) die "neznamy koren patche: $name" ;;
  esac
  echo "== $name -> sources/$component"
  patch -d "$stage/sources/$component" -p1 --batch --forward --fuzz=0 < "$patch_file"
  digest="$(shasum -a 256 "$patch_file" | awk '{print $1}')"
  printf '%s  %s\n' "$digest" "$name" >> "$stage/prepare-sources.manifest"
done
mv "$stage/sources" "$build/sources"
mv "$stage/$ARCHIVE_NAME" "$stage/prepare-sources.manifest" "$build/"
echo "Hotovo: $build"
echo "Pro sestaveni nastav MACWINE_BUILD na tento adresar."

#!/bin/bash
# Prepares a public MacWine release with automatic updates (Sparkle 2).
#
#   MACWINE_RELEASE_REPO=<owner>/<repo> ./release.sh <version>      e.g. ./release.sh 1.0.0
#
# Result in $MACWINE_BUILD/app-stage/release/:
#   MacWine-<version>.zip + appcast.xml        -> upload to GitHub release "v<version>"
#   macwine-runtime-<runtime>.tar.xz           -> upload to GitHub release "runtime-<runtime>" (only when it is new)
# Update archives are signed with the maintainer's EdDSA key from the macOS Keychain (Sparkle generate_keys).
# The private key never leaves the Keychain and must never be committed.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
BUILD="${MACWINE_BUILD:-$HOME/macwine-build}"
VERSION="${1:-}"
REPO="${MACWINE_RELEASE_REPO:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo "usage: MACWINE_RELEASE_REPO=<owner>/<repo> $0 <version, e.g. 1.0.0>"; exit 1; }
[ -n "$REPO" ] || { echo "Set MACWINE_RELEASE_REPO=<owner>/<repo>"; exit 1; }

SPARKLE_VERSION=2.10.0
SPARKLE_SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
TOOLS="$BUILD/sparkle-tools"
if [ ! -x "$TOOLS/bin/generate_appcast" ]; then
  mkdir -p "$TOOLS"
  curl -fL --retry 3 -o "$TOOLS/Sparkle-$SPARKLE_VERSION.tar.xz" \
    "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
  [ "$(shasum -a 256 "$TOOLS/Sparkle-$SPARKLE_VERSION.tar.xz" | cut -d' ' -f1)" = "$SPARKLE_SHA256" ] || { echo "Sparkle tools checksum mismatch"; exit 1; }
  tar -xJf "$TOOLS/Sparkle-$SPARKLE_VERSION.tar.xz" -C "$TOOLS" bin
fi

# Public key from the Keychain (created once by the maintainer with: $TOOLS/bin/generate_keys)
PUBKEY=""
if out="$("$TOOLS/bin/generate_keys" -p 2>/dev/null)" && [ "$(printf '%s' "$out" | base64 -d 2>/dev/null | wc -c | tr -d ' ')" = 32 ]; then
  PUBKEY="$out"
fi
if [ -z "$PUBKEY" ]; then
  echo "No Sparkle signing key in your Keychain yet. Create it once with:"
  echo "  $TOOLS/bin/generate_keys"
  echo "and back it up (generate_keys -x <file>) somewhere safe - losing it means users cannot be updated."
  exit 1
fi

MACWINE_VERSION="$VERSION" MACWINE_SPARKLE_PUBLIC_KEY="$PUBKEY" MACWINE_RELEASE_REPO="$REPO" \
  "$SRC/package-app.sh" --release

OUT="$BUILD/app-stage/release"
APPCAST_DIR="$OUT/appcast"
mkdir -p "$APPCAST_DIR"
cp "$OUT/MacWine-$VERSION.zip" "$APPCAST_DIR/"
# generate_appcast signs the zip with the Keychain key and writes appcast.xml
"$TOOLS/bin/generate_appcast" --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" "$APPCAST_DIR"
# Never publish an unsigned appcast: every update must carry an EdDSA signature.
if ! grep -q 'sparkle:edSignature=' "$APPCAST_DIR/appcast.xml"; then
  rm -f "$APPCAST_DIR/appcast.xml"
  echo "appcast.xml is not signed (signing key missing?) - release aborted"; exit 1
fi
cp "$APPCAST_DIR/appcast.xml" "$OUT/appcast.xml"

RT_ARCHIVE="$(ls -t "$OUT"/macwine-runtime-*.tar.xz | head -1)"
RT_VERSION="$(basename "$RT_ARCHIVE" .tar.xz)"; RT_VERSION="${RT_VERSION#macwine-runtime-}"
cat <<INFO

Release $VERSION is ready in $OUT
1. GitHub release "v$VERSION": upload
     $OUT/MacWine-$VERSION.zip
     $OUT/appcast.xml
2. GitHub release "runtime-$RT_VERSION" (only if it does not exist yet): upload
     $RT_ARCHIVE
Installed copies of MacWine will offer the update automatically (MacWine > Check for Updates…).
INFO

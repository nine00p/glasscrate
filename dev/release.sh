#!/bin/bash
# Packages the tested app from beta/ into a DMG in releases/, named by its version.
# The DMG opens to show Glass Crate next to an Applications folder shortcut,
# so installing is just dragging one onto the other. It also includes "Read Me.html"
# (from this folder) with the version number filled in.
# Run this only after you've tested the beta build and you're happy with it.
set -e
cd "$(dirname "$0")"

APP="../beta/Glass Crate.app"
OUT="../releases"

if [ ! -d "$APP" ]; then
  echo "No app found in the beta folder. Run build.sh first."
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")"
DMG="$OUT/Glass Crate $VERSION.dmg"
mkdir -p "$OUT"

if [ -e "$DMG" ]; then
  echo "Glass Crate $VERSION is already in releases."
  read -r -p "Replace it? (y/n) " answer
  [ "$answer" = "y" ] || { echo "Nothing changed."; exit 0; }
  rm -f "$DMG"
fi

# Put the app and an Applications shortcut together in a temporary folder
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Glass Crate.app"     # ditto keeps the app's signature and icon intact
ln -s /Applications "$STAGE/Applications"

# Read Me: copy it in and replace {{VERSION}} with the real version number
if [ -f "Read Me.html" ]; then
  sed "s/{{VERSION}}/$VERSION/g" "Read Me.html" > "$STAGE/Read Me.html"
else
  echo "Warning: Read Me.html not found in the dev folder. The DMG won't include it."
fi

# Turn that folder into a compressed disk image (hdiutil comes with every Mac)
echo "Building the DMG..."
hdiutil create -volname "Glass Crate $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo
echo "Done! Released: releases/Glass Crate $VERSION.dmg (build $BUILD)"
echo "Before the next build, bump VERSION at the top of build.sh (e.g. $VERSION -> the next patch number)."
open -R "$DMG"

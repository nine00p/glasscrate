#!/bin/bash
# Builds "Glass Crate.app" for testing.
#
# Folder layout (this script lives in dev/):
#   glasscrate/dev/       the code: .swift files, About.md, CHANGELOG.md, build.sh, release.sh, restore.sh
#   glasscrate/artwork/   icon.png (and the icon's source file)
#   glasscrate/beta/      the app this script builds, for testing
#   glasscrate/releases/  tested versions zipped by release.sh
#
# The finished app runs on both Apple Silicon and Intel Macs (macOS 13 Ventura or newer).
set -e
cd "$(dirname "$0")"

# ===== Version: change this when you start a new version =====
#   major.minor.patch
#   patch  1.0.0 -> 1.0.1   fixes and small tweaks
#   minor  1.0.x -> 1.1.0   a new feature
#   major  1.x.x -> 2.0.0   a big update: new interface, new abilities
VERSION="1.3.0"
# ===============================================================

# The build number counts up by itself every time this script runs (saved in build-number.txt),
# so every test build is unique. Shown in the About window as "Version 1.0.0 (build 12)".
BUILD=$(( $(cat build-number.txt 2>/dev/null || echo 0) + 1 ))
echo "$BUILD" > build-number.txt

ICON="../artwork/icon.png"
OUT="../beta"

# Apple's Command Line Tools are needed to build (only needed to build the app, not to run it)
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Apple's Command Line Tools are needed. An installer window will open."
  echo "When it finishes, run this script again."
  xcode-select --install
  exit 1
fi

mkdir -p "$OUT"
APP="$OUT/Glass Crate.app"
SWIFTC="$(xcrun --find swiftc)"

echo "Building Glass Crate..."
echo "Compiler: $("$SWIFTC" --version 2>&1 | head -1)"
rm -rf "$APP" build
mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Every .swift file in this folder is built into the app (GlassCrate.swift plus all the add-on files).
SOURCES=(*.swift)
echo "Source files: ${SOURCES[*]}"

build_with() {
  "$SWIFTC" -O -parse-as-library -sdk "$1" -target arm64-apple-macos13.0  "${SOURCES[@]}" -o build/glasscrate-arm64  2> build/err.txt &&
  "$SWIFTC" -O -parse-as-library -sdk "$1" -target x86_64-apple-macos13.0 "${SOURCES[@]}" -o build/glasscrate-x86_64 2>> build/err.txt
}

# Try the default SDK first, then every other installed SDK, until one matches the compiler.
FOUND=""
for SDK in "$(xcrun --show-sdk-path)" /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk; do
  [ -d "$SDK" ] || continue
  echo "Trying $(basename "$SDK")..."
  if build_with "$SDK"; then FOUND="$SDK"; break; fi
  if ! grep -q "not supported by the compiler" build/err.txt; then
    echo
    echo "Build error (details below):"
    cat build/err.txt
    exit 1
  fi
done

if [ -z "$FOUND" ]; then
  echo
  echo "None of the installed SDKs match the compiler. Installed SDKs:"
  ls -1 /Library/Developer/CommandLineTools/SDKs/
  echo
  echo "Fix: check System Settings > General > Software Update for a Command Line Tools update."
  echo "If there isn't one, reinstall the tools with these two commands, then run this script again:"
  echo "  sudo rm -rf /Library/Developer/CommandLineTools"
  echo "  xcode-select --install"
  exit 1
fi

echo "Built with $(basename "$FOUND")"
lipo -create build/glasscrate-arm64 build/glasscrate-x86_64 -output "$APP/Contents/MacOS/GlassCrate"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>          <string>GlassCrate</string>
    <key>CFBundleIdentifier</key>          <string>com.nine00p.glasscrate</string>
    <key>CFBundleName</key>                <string>Glass Crate</string>
    <key>CFBundleDisplayName</key>         <string>Glass Crate</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleShortVersionString</key>  <string>$VERSION</string>
    <key>CFBundleVersion</key>             <string>$BUILD</string>
    <key>LSMinimumSystemVersion</key>      <string>13.0</string>
    <key>NSHighResolutionCapable</key>     <true/>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Glass Crate saves your downloads here.</string>
</dict>
</plist>
PLIST

# Text for the About and What's New windows
if [ -f About.md ]; then
  cp About.md "$APP/Contents/Resources/About.md"
else
  echo "Warning: About.md not found. The About window will be empty."
fi
if [ -f CHANGELOG.md ]; then
  cp CHANGELOG.md "$APP/Contents/Resources/CHANGELOG.md"
else
  echo "Warning: CHANGELOG.md not found. The What's New window will be empty."
fi

# App icon: a square PNG (1024x1024 is best) at artwork/icon.png
if [ -f "$ICON" ]; then
  echo "Adding icon..."
  mkdir -p build/AppIcon.iconset
  for s in 16 32 128 256 512; do
    d=$((s * 2))
    sips -s format png -z $s $s "$ICON" --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -s format png -z $d $d "$ICON" --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
  plutil -insert CFBundleIconFile -string AppIcon "$APP/Contents/Info.plist"
else
  echo "No icon found at artwork/icon.png, using the default icon."
fi

codesign --force --deep --sign - "$APP"
rm -rf build

# ===== Snapshot: save a restore point of the code for this build =====
# Uses Git (included with Apple's Command Line Tools). Everything stays on this Mac.
# To go back to an earlier build, run restore.sh.
# Skipped in a copy from GitHub (it's connected to GitHub), so it never adds commits there.
if [ -n "$(git remote 2>/dev/null)" ]; then
  echo "(GitHub copy: no automatic snapshot.)"
else
  if [ ! -d .git ]; then
    git init -q
    printf "build/\nbuild-number.txt\n.DS_Store\n" > .gitignore
  fi
  git add -A
  if git diff --cached --quiet; then
    echo "No code changes since the last snapshot."
  else
    git -c user.name="Glass Crate" -c user.email="build@localhost" \
      commit -q -m "Build $BUILD ($VERSION)"
    echo "Snapshot saved: Build $BUILD ($VERSION)"
  fi
fi

echo
echo "Done! Built Glass Crate $VERSION (build $BUILD) in the beta folder."
echo "Test it, then run release.sh to zip it into releases."
open -R "$APP"

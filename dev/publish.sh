#!/bin/bash
# Copies the public files into the GitHub folder (glasscrate-public/Glass Crate, inside your project folder),
# in the same layout as your project:
#   glasscrate-public/Glass Crate/
#     README.md, LICENSE, .gitignore
#     dev/       the code, build scripts, About.md, CHANGELOG.md, Read Me.html
#     artwork/   icon.png
# Then commit and push with GitHub Desktop.
#
# PRIVATE, never copied: ROADMAP.md, TESTLOG*.md, build-number.txt, your build snapshots (.git here),
# and the beta and releases folders (built apps and DMGs go on GitHub's Releases page instead).
set -e
cd "$(dirname "$0")"

DEST="../glasscrate-public/Glass Crate"
mkdir -p "$DEST/dev" "$DEST/artwork"

# Code: replace all .swift files, so a renamed or deleted file doesn't linger on GitHub
rm -f "$DEST/dev/"*.swift
cp *.swift "$DEST/dev/"

# Scripts and the files the app and DMG include
for f in build.sh release.sh restore.sh publish.sh gitignore-public About.md CHANGELOG.md "Read Me.html"; do
  cp "$f" "$DEST/dev/"
done

# The front page, the license, and what Git should ignore
cp README.md LICENSE "$DEST/"
cp gitignore-public "$DEST/.gitignore"

# The app icon
cp ../artwork/icon.png "$DEST/artwork/icon.png"

echo "Public files copied to glasscrate-public/Glass Crate."
echo "Next: open GitHub Desktop, review the changes, write a short summary, then Commit and Push."
open "$DEST"

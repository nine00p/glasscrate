#!/bin/bash
# Rolls the code in dev/ back to an earlier build.
# Nothing is ever lost: your current code is saved as a snapshot first,
# and the restore itself becomes a new snapshot you can undo the same way.
set -e
cd "$(dirname "$0")"

GIT=(git -c user.name="Glass Crate" -c user.email="build@localhost")

if [ ! -d .git ]; then
  echo "No snapshots yet. They're saved automatically each time build.sh runs."
  exit 1
fi

echo "Recent snapshots (newest first):"
echo
git log -20 --format="  %s   —   %cr"
echo
read -r -p "Restore to which build number? (or press Enter to cancel) " N
[ -n "$N" ] || { echo "Nothing changed."; exit 0; }

COMMIT="$(git log --format=%H --grep="^Build $N (" -1)"
if [ -z "$COMMIT" ]; then
  echo "Couldn't find Build $N in the snapshots."
  exit 1
fi

# Save whatever is here now, so the restore can always be undone
git add -A
if ! git diff --cached --quiet; then
  "${GIT[@]}" commit -q -m "Unsaved changes before restoring to build $N"
  echo "Saved your current changes as a snapshot first."
fi

# Put every file back exactly as it was in that build (files added later are removed)
git restore --source="$COMMIT" --staged --worktree -- .
git add -A
if git diff --cached --quiet; then
  echo "The code already matches Build $N."
else
  "${GIT[@]}" commit -q -m "Restored to build $N"
  echo
  echo "Done! The code is back to Build $N."
fi
echo "Run build.sh to build that version into the beta folder."

#!/bin/bash
#
# Reverts the always-logged-in patch applied by patch_always_logged_in.sh,
# restoring the original file from its backup. Run as root on the ASL node.
#
set -euo pipefail

TARGET="/usr/lib/python3/dist-packages/asl_allmon/allmon3_server/__init__.py"

if [ ! -f "$TARGET" ]; then
    ALT=$(python3 -c "import asl_allmon.allmon3_server as m; print(m.__file__)" 2>/dev/null || true)
    if [ -n "$ALT" ] && [ -f "$ALT" ]; then
        TARGET="$ALT"
    else
        echo "ERROR: could not locate asl_allmon/allmon3_server/__init__.py" >&2
        exit 1
    fi
fi

echo "Target: $TARGET"

if ! grep -q "ALLMON3_ALWAYS_LOGGED_IN" "$TARGET"; then
    echo "Not patched. Nothing to do."
    exit 0
fi

BACKUP=$(ls -1t "${TARGET}".orig.* 2>/dev/null | head -n1 || true)
if [ -z "$BACKUP" ] || [ ! -f "$BACKUP" ]; then
    echo "ERROR: no backup found (${TARGET}.orig.*)" >&2
    exit 1
fi

echo "Restoring from $BACKUP"
cp -p "$BACKUP" "$TARGET"

if grep -q "ALLMON3_ALWAYS_LOGGED_IN" "$TARGET"; then
    echo "ERROR: restored file still contains patch marker, aborting restart" >&2
    exit 1
fi

echo "Verifying syntax..."
python3 -m py_compile "$TARGET"

echo "Restarting allmon3.service..."
systemctl restart allmon3.service

echo "Done. Restored from $BACKUP"

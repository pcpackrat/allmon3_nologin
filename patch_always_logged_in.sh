#!/bin/bash
#
# Patches an installed Allmon3 to always report "Logged In" and skip the
# auth/restriction gate on command execution. Run as root on the ASL node.
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

if grep -q "ALLMON3_ALWAYS_LOGGED_IN" "$TARGET"; then
    echo "Already patched. Nothing to do."
    exit 0
fi

BACKUP="${TARGET}.orig.$(date +%Y%m%d%H%M%S)"
cp -p "$TARGET" "$BACKUP"
echo "Backup saved to $BACKUP"

python3 - "$TARGET" <<'PYEOF'
import sys

path = sys.argv[1]
with open(path, "r") as f:
    src = f.read()

marker = "# ALLMON3_ALWAYS_LOGGED_IN patch applied"

old1 = '''            if c[2] == "check":
                session = await get_session(request)
                session["last_auth_check"] = time.time()
                r_json = self.__get_json_security("No Session")
                if "auth_sess" in session:
                    if session["auth_sess"] in self.server_security.session_db:
                        r_json = self.__get_json_success("Logged In")'''

new1 = '''            if c[2] == "check":  ''' + marker + '''
                session = await get_session(request)
                session["last_auth_check"] = time.time()
                r_json = self.__get_json_success("Logged In")'''

old2 = '''            r_json = None
            user_is_authenticated = False
            if "auth_sess" in session:
                if session["auth_sess"] in self.server_security.session_db:
                    user_is_authenticated = True
                    cmd = req.get("cmd")
                    user = self.server_security.session_db[session["auth_sess"]].user
                    node = int(req.get("node"))
                    uncombo = f"{user}{node}"

                    user_is_restricted = False
                    if user in self.server_security.restricted_users:
                        if uncombo not in self.server_security.restrictdb:
                            log.info("%s restricted from commands on node %s", user, node)
                            user_is_restricted = True
                        else:
                            log.info("%s has restrictions but permitted to node %s", user, node)
                    else:
                        log.info("%s has no node restrictions", user)

            if user_is_authenticated and not user_is_restricted:'''

new2 = '''            r_json = None
            cmd = req.get("cmd")
            node = int(req.get("node"))
            user_is_authenticated = True
            user_is_restricted = False

            if user_is_authenticated and not user_is_restricted:'''

if old1 not in src:
    print("ERROR: patch 1 anchor text not found; file may differ from expected version", file=sys.stderr)
    sys.exit(2)
if old2 not in src:
    print("ERROR: patch 2 anchor text not found; file may differ from expected version", file=sys.stderr)
    sys.exit(2)

src = src.replace(old1, new1, 1)
src = src.replace(old2, new2, 1)

with open(path, "w") as f:
    f.write(src)

print("Patched OK")
PYEOF

echo "Verifying syntax..."
if ! python3 -m py_compile "$TARGET"; then
    echo "ERROR: patched file failed to compile, restoring backup" >&2
    cp -p "$BACKUP" "$TARGET"
    exit 1
fi

echo "Restarting allmon3.service..."
systemctl restart allmon3.service

echo "Done. Backup at $BACKUP"

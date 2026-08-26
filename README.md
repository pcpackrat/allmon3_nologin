# allmon3-nologin

Two scripts for an installed Allmon3 (AllStarLink monitoring dashboard): `patch_always_logged_in.sh` puts it into a permanently logged-in state, always reporting "Logged In" and skipping its auth/restriction gate on command execution; `unpatch_always_logged_in.sh` reverses that, restoring the original login behavior. Useful for nodes where the login prompt is unwanted (e.g. LAN-only or otherwise access-controlled deployments).

Run both as root on the ASL node itself, not on a dev machine.

## patch_always_logged_in.sh

- Locates the installed `asl_allmon/allmon3_server/__init__.py` (default path, falling back to a `python3 -c "import ..."` lookup if not found there).
- Backs up the original file to `<file>.orig.<timestamp>` before touching it.
- Rewrites two blocks in the file:
  - the session `"check"` handler, so it always returns `"Logged In"` instead of checking `auth_sess` against the session DB.
  - the command-execution path, so `user_is_authenticated` and `not user_is_restricted` are hardcoded true/false instead of being derived from the session.
- Is idempotent: if the patch marker (`ALLMON3_ALWAYS_LOGGED_IN`) is already present, it exits without changes.
- Aborts if the expected source text isn't found (protects against silently mismatching an unexpected Allmon3 version).
- Verifies the patched file compiles (`python3 -m py_compile`); on failure it restores the backup automatically.
- Restarts `allmon3.service` on success.

## unpatch_always_logged_in.sh

- Locates the same target file.
- Exits immediately if the patch marker isn't present (nothing to revert).
- Finds the most recent `<file>.orig.*` backup and restores it.
- Verifies the restored file no longer contains the patch marker and compiles cleanly.
- Restarts `allmon3.service`.

## Usage

```bash
sudo ./patch_always_logged_in.sh
# ... later, to revert ...
sudo ./unpatch_always_logged_in.sh
```

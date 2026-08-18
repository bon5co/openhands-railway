#!/bin/sh
# Railway shim for OpenHands Agent Canvas.
#
# Runs before upstream's /opt/agent-canvas/entrypoint.sh and does three things
# that entrypoint cannot do for itself on Railway:
#
#   1. Refuses to boot without a session API key. Upstream generates one when it
#      is missing, which is correct for `docker run` on a laptop and wrong for a
#      public URL: the key would rotate on every redeploy that cannot write the
#      volume, and there would be no stable credential for the operator.
#   2. Repairs volume ownership. Railway mounts volumes as uid 0; the image runs
#      as uid 10001 (openhands) with passwordless sudo.
#   3. Sizes nothing else - upstream reads $PORT itself and the proxy binds it.
set -eu

log() { printf '[railway] %s\n' "$*"; }

if [ -z "${OH_SESSION_API_KEYS_0:-}" ] && [ -z "${LOCAL_BACKEND_API_KEY:-}" ]; then
    cat >&2 <<'MSG'
[railway] FATAL: OH_SESSION_API_KEYS_0 is empty.

This instance is served on a public URL and the OpenHands agent has shell
access to its own container. Without a session API key the agent server runs
unsecured. Set OH_SESSION_API_KEYS_0 to a long random string and redeploy.
MSG
    exit 1
fi

# Upstream's entrypoint writes secret-key.txt / api-key.txt and the automation
# SQLite database under these paths. A uid-0 mount makes every one of those
# writes fail; the automation server then dies in its Alembic migration with
# "unable to open database file" while the rest of the container looks fine.
for d in /home/openhands/.openhands /projects; do
    [ -d "$d" ] || continue
    owner="$(stat -c %u:%g "$d")"
    if [ "$owner" != "10001:10001" ]; then
        log "repairing $d ownership (was $owner)"
        sudo -n chown -R openhands:openhands "$d"
        log "$d now $(stat -c %u:%g "$d")"
    else
        log "$d already $owner"
    fi
done

exec /opt/agent-canvas/entrypoint.sh "$@"

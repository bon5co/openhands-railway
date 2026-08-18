# OpenHands Agent Canvas, packaged for Railway.
#
# Upstream ships a single all-in-one image (agent server + automation server +
# static frontend/ingress). Two things make it unsafe or unusable when that
# image is put behind a public Railway domain:
#
#   1. The stock entrypoint passes --session-api-key to the static server, which
#      injects the session key into the served index.html. Any anonymous visitor
#      can read it out of the page and drive the agent's shell. Upstream ships
#      the fix (--auth-required) but only wires it to an optional secondary port
#      that is never used in a normal deploy. We move the main port onto it.
#   2. Railway mounts volumes owned by uid 0 while the image runs as uid 10001,
#      so the automation server's SQLite migrations fail and it exits. The base
#      image grants the runtime user passwordless sudo, so ownership can be
#      repaired before upstream's entrypoint runs.
FROM ghcr.io/openhands/agent-canvas:1.14.0

USER root

# Serve the frontend WITHOUT baking the session key into the page. Upstream's
# static server treats --session-api-key and --auth-required as mutually
# exclusive, so this is a substitution, not an addition. Only the first
# (main-port) invocation is touched; the optional PUBLIC_MODE_PORT server below
# it already passes --auth-required.
RUN sed -i '0,/^  --session-api-key "\$EFFECTIVE_SESSION_KEY" \\$/s||  --auth-required \\|' \
        /opt/agent-canvas/entrypoint.sh && \
    grep -q -- '--auth-required' /opt/agent-canvas/entrypoint.sh && \
    ! grep -q -- '--session-api-key "\$EFFECTIVE_SESSION_KEY"' /opt/agent-canvas/entrypoint.sh

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod 0755 /usr/local/bin/railway-entrypoint.sh

ENV DO_NOT_TRACK=1

USER openhands

EXPOSE 8000
ENTRYPOINT ["tini", "--", "/usr/local/bin/railway-entrypoint.sh"]

# openhands-railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/openhands-or-just-updated-ai-coding-agen?referralCode=Z1xivh&utm_medium=integration&utm_source=template&utm_campaign=generic)

**Deploy on Railway:** [OpenHands template](https://railway.com/deploy/openhands-or-just-updated-ai-coding-agen?referralCode=Z1xivh&utm_medium=integration&utm_source=template&utm_campaign=generic)

Wrapper image for deploying [OpenHands Agent Canvas](https://github.com/OpenHands/OpenHands)
on Railway. Published as `ghcr.io/bon5co/openhands-railway:1.14.0`.

Base image: `ghcr.io/openhands/agent-canvas:1.14.0` (upstream's official all-in-one —
agent server on 18000, automation server on 18001, static frontend + ingress on `$PORT`).

## What this changes

### 1. The session API key is no longer served to anonymous visitors

Upstream's Docker entrypoint launches the static server with `--session-api-key`, which
injects the key into the served `index.html` as `window.__AGENT_CANVAS_SESSION_API_KEY__`
and into `localStorage`. That is the right default for `docker run` on a laptop, where the
port is not reachable from anywhere else. Behind a public Railway domain it means any
visitor can read the credential out of the page and then drive the agent's shell:

```
$ curl -s $URL/canvas/ | grep -o '__AGENT_CANVAS_SESSION_API_KEY__ *= *"[^"]*"'
__AGENT_CANVAS_SESSION_API_KEY__="188d90…8f5f"

$ curl -s -X POST $URL/api/bash/execute_bash_command \
    -H "X-Session-API-Key: 188d90…8f5f" -H 'content-type: application/json' \
    -d '{"command":"id"}'
{"exit_code":0,"stdout":"uid=10001(openhands) gid=10001(openhands) groups=10001(openhands),27(sudo)\n",…}
```

Upstream ships the fix — `static-server.mjs` supports `--auth-required`, which serves the
same frontend with a key-entry screen instead of a baked key — but the entrypoint only
wires it to an *optional* second server on `PUBLIC_MODE_PORT`, used by end-to-end tests.
The main port never gets it. This image substitutes `--auth-required` for
`--session-api-key` on the main port (they are mutually exclusive in the static server, so
it is a substitution, not an addition) and the build asserts the substitution took.

The API surface itself was already authenticated — `check_session_api_key` guards the whole
`/api` router and the WebSocket handshake. `/health`, `/alive`, `/ready` and `/server_info`
stay unauthenticated, which is what the Railway healthcheck needs.

### 2. It refuses to boot without a session API key

`session_api_keys: []` means "unsecured" in the agent server's own words. Upstream generates
a key when none is set and persists it to the volume; the shim requires one to be supplied
instead, so the credential is stable, is not derived from a file that a failed volume write
would silently regenerate, and is chosen by the deploy rather than by the container.

### 3. Volume ownership is repaired before upstream's entrypoint runs

Railway mounts volumes owned by uid 0. The image runs as `openhands` (uid 10001), so
upstream's entrypoint cannot write under `/home/openhands/.openhands` and the automation
server dies in its Alembic migration:

```
Failed to apply SQLite migrations: (sqlite3.OperationalError) unable to open database file
RuntimeError: SQLite migration failed. Database may be inconsistent
Application startup failed. Exiting.
```

The base image grants `openhands` passwordless sudo, so the shim `chown`s the mount and then
`exec`s upstream's entrypoint unchanged.

## Notes

- The frontend is a Vite build with `VITE_BASE_PATH=/canvas` compiled in, so `/` answers a
  308 redirect to `/canvas/`. That is upstream behaviour and cannot be changed at runtime.
- Upstream's entrypoint reads `$PORT` (`PORT="${PORT:-${CONFIG_PROXY_PORT:-8000}}"`), so the
  Railway-injected port is honoured and the healthcheck dials the right listener.
- `OH_SECRET_KEY` encrypts stored LLM credentials. Set it explicitly; if it is unset the
  entrypoint generates one onto the volume, and anything that stops that write from landing
  makes previously stored secrets undecryptable.
- Telemetry: set `DO_NOT_TRACK=1` to disable upstream's PostHog exporter.

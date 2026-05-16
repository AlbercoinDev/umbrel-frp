# AGENTS.md — umbrel-frp

## Project structure

```
vps/                          VPS server files → deploy to /opt/frp-vps-admin/
  install.sh                  Idempotent installer (runs as root, tolerates re-runs)
  server.py                   FastAPI admin API (listens 127.0.0.1:12000)
  Caddyfile                   TLS reverse-proxy vps.tudominio.com → localhost:12000
umbrel/                       Umbrel app → deploy to /umbrel/apps/frp-client/
  umbrel-app.yml              App Store manifest v1
  docker-compose.yml          Single service: main (build + frpc subprocess)
  Dockerfile                  python:3.11-slim + procps + curl + pip deps + frpc binary
  app/
    main.py                   FastAPI backend (CRUD, frpc.toml atomic writes, VPS sync, frpc subprocess mgmt)
    templates/index.html      Dark Umbrel-style UI with setup/add/delete
```

## Architecture

- **VPS**: Caddy handles TLS termination on port 443 → proxies to `server.py` on `127.0.0.1:12000`. The API validates a Bearer token from `/opt/frp-vps-admin/initial_token.txt`, writes `/etc/frp/frps.toml` atomically, and runs `sudo systemctl restart frps`.
- **Umbrel**: Single container (`main`) runs both the FastAPI UI (port 1234) and the `frpc` binary as a subprocess. `network_mode: host` gives direct access to `127.0.0.1` services (Bitcoin, Electrs). Config writes are atomic; frpc reloads via SIGHUP.
- **No second container**: Official Umbrel apps with `network_mode: host` use a single container. Two containers with host networking break Umbrel's install flow (cross-container `pkill` fails, race conditions on config, health check failures).
- **Security**: All client→VPS traffic is HTTPS only (Caddy TLS). Token is 32-byte hex from `openssl rand`. VPS API is bound to localhost only.
- **Idempotent install**: `install.sh` uses sentinel file `.installed` and guards (e.g., `if ! id -u vpsadmin`) to tolerate re-runs.

## Key conventions

- All FRP config writes use temp-file + `shutil.move` (atomic).
- DB persistence: `/app/data/db.json` (mounted from `${APP_DATA_DIR}` in compose).
- `frps` runs as user `vpsadmin` with sudoers NOPASSWD for `systemctl restart frps`.
- Change `vps.tudominio.com` in `Caddyfile` to the real domain before deploy.
- Single container with `network_mode: host` — no `app_proxy`, no `pid: host`, no cross-container communication.
- `uvicorn` without `[standard]` to avoid ARM compilation of `uvloop`/`httptools`.
- Always mount FRP config as a directory (`/etc/frp:/etc/frp`), never as a single file, to prevent Docker creating a directory in the file's place.
- App store app ID must start with store prefix, e.g. `albercoin-store-frp-client`.
- frpc binary is downloaded at build time via `curl` from GitHub releases; architecture is auto-detected via `uname -m`.

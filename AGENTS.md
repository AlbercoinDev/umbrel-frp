# AGENTS.md — umbrel-frp

## Project structure

```
vps/                          VPS server files → deploy to /opt/frp-vps-admin/
  install.sh                  Idempotent installer (runs as root, tolerates re-runs)
  server.py                   FastAPI admin API (listens 127.0.0.1:12000)
  Caddyfile                   TLS reverse-proxy vps.tudominio.com → localhost:12000
umbrel/                       Umbrel app → deploy to /umbrel/apps/frp-client/
  umbrel-app.yml              App Store manifest v1
  docker-compose.yml          Two services: frp_manager (build) + frpc_client (image)
  Dockerfile                  python:3.11-slim + procps + pip deps
  app/
    main.py                   FastAPI backend (CRUD, frpc.toml atomic writes, VPS sync)
    templates/index.html      Dark Umbrel-style UI with setup/add/delete
```

## Architecture

- **VPS**: Caddy handles TLS termination on port 443 → proxies to `server.py` on `127.0.0.1:12000`. The API validates a Bearer token from `/opt/frp-vps-admin/initial_token.txt`, writes `/etc/frp/frps.toml` atomically, and runs `sudo systemctl restart frps`.
- **Umbrel**: `frp_manager` (Python) writes `/etc/frp/frpc.toml` atomically with `transport.useEncryption = true` on every proxy, syncs to VPS via `POST https://<domain>/api/sync`, then restarts `frpc` via `pkill` (cross-container via `pid: host`). `frpc_client` is the official `fatedier/frpc:v0.54.0` image. Both use `network_mode: host + pid: host`.
- **No `app_proxy`**: host-networked apps omit the `app_proxy` service. Umbrel proxies directly to `localhost:<port>`.
- **Security**: All client→VPS traffic is HTTPS only (Caddy TLS). Token is 32-byte hex from `openssl rand`. VPS API is bound to localhost only.
- **Idempotent install**: `install.sh` uses sentinel file `.installed` and guards (e.g., `if ! id -u vpsadmin`) to tolerate re-runs.

## Key conventions

- All FRP config writes use temp-file + `shutil.move` (atomic).
- DB persistence: `/app/data/db.json` (mounted from `${APP_DATA_DIR}` in compose).
- `frps` runs as user `vpsadmin` with sudoers NOPASSWD for `systemctl restart frps`.
- Change `vps.tudominio.com` in `Caddyfile` to the real domain before deploy.
- Cross-container `pkill frpc` requires `pid: "host"` on both containers.
- `uvicorn` without `[standard]` to avoid ARM compilation of `uvloop`/`httptools`.
- Always mount FRP config as a directory (`/etc/frp:/etc/frp`), never as a single file, to prevent Docker creating a directory in the file's place.
- App store app ID must start with store prefix, e.g. `albercoin-store-frp-client`.

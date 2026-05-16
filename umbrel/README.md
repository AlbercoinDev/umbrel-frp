# FRP Client — Umbrel App

Aplicación nativa para Umbrel que gestiona túneles FRP desde una interfaz web.

## Deploy

Copiar a `/umbrel/apps/frp-client/` en el nodo Umbrel. La App Store lo reconoce automáticamente.

## Componentes

| Archivo | Rol |
|---|---|
| `umbrel-app.yml` | Manifiesto App Store v1, puerto UI 1234 |
| `docker-compose.yml` | Dos servicios: `frp_manager` (build local) + `frpc_client` (imagen oficial v0.54.0) |
| `Dockerfile` | `python:3.11-slim` con FastAPI, Uvicorn, Jinja2 |
| `app/main.py` | Backend CRUD — persistencia en `data/db.json`, escritura atómica de `frpc.toml`, sincronización HTTPS con VPS, reinicio de `frpc` |
| `app/templates/index.html` | UI oscura estilo Umbrel — estado de conexión, formularios de configuración y tabla de proxies |

## Flujo

1. Configurar dominio VPS + token vía `/setup`
2. Añadir proxies (nombre, puerto local, puerto remoto) — se escribe `frpc.toml`, se sincroniza con VPS, se reinicia `frpc`
3. Eliminar proxies con igual sincronización

## Seguridad

- Todo el tráfico al VPS es HTTPS.
- Cada proxy incluye `transport.useEncryption = true`.
- `network_mode: host` para mapear servicios sin bridges.
- Datos persistentes en `${APP_DATA_DIR}` mapeado a `/app/data/`.

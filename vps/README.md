# frp-vps-admin

Agente administrador del servidor FRP en el VPS.

## Deploy

```bash
sudo ./install.sh
```

Esto instala Caddy, Python, FRP v0.54.0, crea el usuario `vpsadmin`, configura sudoers, genera un token de 32 bytes en `/opt/frp-vps-admin/initial_token.txt`, y activa los services systemd `frps` y `frps-admin`.

## Componentes

| Archivo | Rol |
|---|---|
| `install.sh` | Instalador idempotente (tolera re-ejecuciones) |
| `server.py` | FastAPI en `127.0.0.1:12000` — valida Bearer token, escribe `/etc/frp/frps.toml` atómicamente, reinicia `frps` |
| `Caddyfile` | Proxy inverso TLS: `vps.tudominio.com:443 → localhost:12000` |

## Endpoint

- **`POST /api/sync`** — Recibe `{"proxies": [{"name": "...", "remote_port": N}]}`, regenera `frps.toml` y reinicia el servicio.

## Seguridad

- Todo el tráfico pasa por TLS (Caddy).
- API escucha solo en `127.0.0.1`.
- Token de 32 bytes hex leído desde archivo con permisos `600`.
- `vpsadmin` tiene sudo NOPASSWD únicamente para `systemctl restart frps`.

## Personalizar

Cambiar `vps.tudominio.com` en `Caddyfile` por el dominio real antes de ejecutar `install.sh`.

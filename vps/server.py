import os
import subprocess
import tempfile
import shutil

from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel, Field

app = FastAPI(title="FRP VPS Admin")

TOKEN_PATH = "/opt/frp-vps-admin/initial_token.txt"
FRPS_CONFIG_PATH = "/etc/frp/frps.toml"


def _load_token() -> str:
    try:
        with open(TOKEN_PATH, "r") as f:
            token = f.read().strip()
        if not token:
            raise RuntimeError("Token file is empty")
        return token
    except FileNotFoundError:
        raise RuntimeError(f"Token file not found at {TOKEN_PATH}")


TOKEN = _load_token()


class ProxyItem(BaseModel):
    name: str = Field(
        ...,
        min_length=1,
        max_length=100,
        pattern=r'^[a-zA-Z0-9_-]+$',
    )
    remote_port: int = Field(..., ge=1, le=65535)


class SyncRequest(BaseModel):
    proxies: list[ProxyItem]


def _verify_token(authorization: str | None) -> None:
    if authorization is None:
        raise HTTPException(status_code=401, detail="Missing Authorization header")
    parts = authorization.split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(
            status_code=401, detail="Invalid Authorization header format"
        )
    if parts[1] != TOKEN:
        raise HTTPException(status_code=401, detail="Invalid token")


def _generate_frps_toml(proxies: list[ProxyItem]) -> str:
    lines = ["bindPort = 7000", ""]
    for proxy in proxies:
        lines.append("[[proxies]]")
        lines.append(f'name = "{proxy.name}"')
        lines.append('type = "tcp"')
        lines.append(f"remotePort = {proxy.remote_port}")
        lines.append("")
    return "\n".join(lines)


def _atomic_write(path: str, content: str) -> None:
    dir_path = os.path.dirname(path)
    os.makedirs(dir_path, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=dir_path, prefix=".tmp_", suffix=".toml")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        shutil.move(tmp_path, path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


@app.post("/api/sync")
async def sync(request: SyncRequest, req: Request) -> dict:
    _verify_token(req.headers.get("authorization"))
    try:
        content = _generate_frps_toml(request.proxies)
        _atomic_write(FRPS_CONFIG_PATH, content)
        result = subprocess.run(
            ["sudo", "/usr/bin/systemctl", "restart", "frps"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode != 0:
            raise HTTPException(
                status_code=500,
                detail=f"Failed to restart frps: {result.stderr.strip()}",
            )
        return {"status": "ok", "message": "Configuration synced and frps restarted"}
    except HTTPException:
        raise
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=500, detail="Timeout restarting frps")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Internal error: {str(e)}")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=12000)

#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/frp-vps-admin"
FRP_VERSION="0.54.0"
FRP_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz"
TOKEN_FILE="${INSTALL_DIR}/initial_token.txt"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "${INSTALL_DIR}/.installed" ]; then
    echo "Already installed. Remove ${INSTALL_DIR}/.installed to re-run."
    exit 0
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 python3-pip python3-venv curl

if ! command -v caddy &> /dev/null; then
    curl -fsSL https://caddyserver.com/api/download -o /usr/local/bin/caddy
    chmod +x /usr/local/bin/caddy
fi

TMPDIR=$(mktemp -d)
trap "rm -rf ${TMPDIR}" EXIT
curl -fsSL "${FRP_URL}" -o "${TMPDIR}/frp.tar.gz"
tar -xzf "${TMPDIR}/frp.tar.gz" -C "${TMPDIR}"
cp "${TMPDIR}/frp_${FRP_VERSION}_linux_amd64/frps" /usr/local/bin/frps
chmod +x /usr/local/bin/frps

mkdir -p /etc/frp
mkdir -p "${INSTALL_DIR}"

if [ ! -f "${TOKEN_FILE}" ]; then
    openssl rand -hex 32 > "${TOKEN_FILE}"
    chmod 600 "${TOKEN_FILE}"
fi

if ! id -u vpsadmin &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin vpsadmin
fi

SUDOERS_FILE="/etc/sudoers.d/vpsadmin"
if [ ! -f "${SUDOERS_FILE}" ]; then
    echo "vpsadmin ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart frps" > "${SUDOERS_FILE}"
    chmod 440 "${SUDOERS_FILE}"
fi

cp "${SCRIPT_DIR}/server.py" "${INSTALL_DIR}/server.py"
cp "${SCRIPT_DIR}/Caddyfile" "${INSTALL_DIR}/Caddyfile"

cat > /etc/systemd/system/frps.service << 'EOF'
[Unit]
Description=FRP Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/frps -c /etc/frp/frps.toml
Restart=always
RestartSec=5
User=vpsadmin

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/frps-admin.service << EOF
[Unit]
Description=FRP VPS Admin API
After=network.target frps.service
Requires=frps.service

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/venv/bin/python ${INSTALL_DIR}/server.py
WorkingDirectory=${INSTALL_DIR}
Restart=always
RestartSec=5
User=vpsadmin

[Install]
WantedBy=multi-user.target
EOF

python3 -m venv "${INSTALL_DIR}/venv"
"${INSTALL_DIR}/venv/bin/pip" install fastapi uvicorn

mkdir -p /etc/caddy
if ! grep -q "frps-admin" /etc/caddy/Caddyfile 2>/dev/null; then
    cat "${INSTALL_DIR}/Caddyfile" >> /etc/caddy/Caddyfile
fi

touch "${INSTALL_DIR}/.installed"

systemctl daemon-reload
systemctl enable frps frps-admin
systemctl start frps frps-admin

echo "Installation complete."
echo "Token: $(cat ${TOKEN_FILE})"

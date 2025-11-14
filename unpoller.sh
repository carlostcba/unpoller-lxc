#!/usr/bin/env bash
# Source: https://github.com/unpoller/unpoller
# Source: https://github.com/community-scripts/ProxmoxVE
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVE/raw/branch/main/misc/build.func)

# Copyright (c) 2021-2025 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT
# Modified by: Gemini for User

APP="Unpoller Prom"
var_tags="${var_tags:-monitoring,unifi,prometheus}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

# ---------------------------------------------------------------------------
# FIX CRÍTICO: Sobrescribimos la función del framework que causa el error 404
# En lugar de bajar un script inexistente, inyectamos nuestra lógica localmente.
# ---------------------------------------------------------------------------
function install_script() {
    msg_info "Inyectando script de instalación personalizado..."

    # Creamos el script de instalación en un archivo temporal del HOST
    cat << 'EOF' > /tmp/install_custom_internal.sh
#!/bin/bash
set -e

echo "Iniciando instalación interna..."
apt-get update
apt-get install -y curl wget gnupg apt-transport-https sudo

# --- Install Prometheus ---
echo "Instalando Prometheus..."
useradd --no-create-home --shell /bin/false prometheus || true

LATEST_PROM=$(curl -sL https://api.github.com/repos/prometheus/prometheus/releases/latest | grep '"tag_name":' | sed -E 's/.*"v(.*)",/\1/')
PROM_URL="https://github.com/prometheus/prometheus/releases/download/v${LATEST_PROM}/prometheus-${LATEST_PROM}.linux-amd64.tar.gz"

wget -qO- ${PROM_URL} | tar -xzf - -C /tmp

mv /tmp/prometheus-*/prometheus /usr/local/bin/
mv /tmp/prometheus-*/promtool /usr/local/bin/
chown prometheus:prometheus /usr/local/bin/prometheus
chown prometheus:prometheus /usr/local/bin/promtool

mkdir -p /etc/prometheus /var/lib/prometheus
mv /tmp/prometheus-*/consoles /etc/prometheus
mv /tmp/prometheus-*/console_libraries /etc/prometheus

cat <<YML > /etc/prometheus/prometheus.yml
global:
  scrape_interval: 30s
scrape_configs:
  - job_name: 'unpoller'
    static_configs:
      - targets: ['localhost:9130']
YML

chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

cat <<SERVICE > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file /etc/prometheus/prometheus.yml \
    --storage.tsdb.path /var/lib/prometheus/ \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable --now prometheus

# --- Install Unpoller ---
echo "Instalando Unpoller..."
curl -sL https://golift.io/repo.sh | bash -s - unpoller

# Configurar Unpoller
cat <<CONF > /etc/unpoller/up.conf
[influxdb]
disable = true

[prometheus]
disable = false
http_listen = "0.0.0.0:9130"
report_errors = true

[unifi.defaults]
url = "https://192.168.1.10"
user = "unifipoller"
pass = "CAMBIAME_PASSWORD"
sites = ["all"]
verify_ssl = false
save_ids = true
CONF

systemctl restart unpoller
rm -rf /tmp/prometheus-*
apt-get autoremove -y
apt-get clean
echo "Instalación finalizada correctamente."
EOF

    # Copiamos el script temporal DENTRO del contenedor
    pct push $CTID /tmp/install_custom_internal.sh /tmp/install_custom_internal.sh
    
    # Le damos permisos de ejecución dentro del contenedor
    pct exec $CTID -- chmod +x /tmp/install_custom_internal.sh
    
    # Ejecutamos el script dentro del contenedor
    msg_info "Ejecutando instalación de paquetes..."
    pct exec $CTID -- bash /tmp/install_custom_internal.sh
    
    # Limpiamos
    pct exec $CTID -- rm /tmp/install_custom_internal.sh
    rm /tmp/install_custom_internal.sh
    
    msg_ok "Instalación personalizada completada"
}

function update_script() {
    msg_info "Updating Unpoller Stack"
    apt-get update
    apt-get -y upgrade
    msg_ok "Updated Unpoller Stack"
    exit
}

# Iniciamos la magia (esto llama a build_container, que ahora usará nuestro install_script modificado)
start
build_container
description

msg_ok "Completed Successfully!"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${GN}Please edit /etc/unpoller/up.conf inside the container.${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Prometheus: http://${IP}:9090${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Unpoller Metrics: http://${IP}:9130/metrics${CL}"
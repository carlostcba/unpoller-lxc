#!/usr/bin/env bash
# Source: https://github.com/unpoller/unpoller
# Source: https://github.com/community-scripts/ProxmoxVE
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVE/raw/branch/main/misc/build.func)

# Copyright (c) 2021-2025 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT
# Modified by: Gemini for User (Only Prometheus + Unpoller)

APP="Unpoller Prom"
var_tags="${var_tags:-monitoring,unifi,prometheus}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

# --- FIX: Override para evitar que busque el script oficial ---
function configure_container() {
  return
}
# --------------------------------------------------------------

header_info "$APP"
variables
color
catch_errors

function update_script() {
  msg_info "Updating Unpoller Stack"
  apt-get update
  apt-get -y upgrade
  msg_ok "Updated Unpoller Stack"
  exit
}

function install_stack() {
  msg_info "Updating package lists and installing dependencies"
  $STD apt-get update
  $STD apt-get install -y curl wget gnupg apt-transport-https sudo
  msg_ok "Dependencies installed"

  # Install Prometheus
  msg_info "Installing Prometheus"
  # Crear usuario prometheus para seguridad
  useradd --no-create-home --shell /bin/false prometheus || true
  
  LATEST_PROM=$(curl -sL https://api.github.com/repos/prometheus/prometheus/releases/latest | grep '"tag_name":' | sed -E 's/.*"v(.*)",/\1/')
  PROM_URL="https://github.com/prometheus/prometheus/releases/download/v${LATEST_PROM}/prometheus-${LATEST_PROM}.linux-amd64.tar.gz"
  
  wget -qO- ${PROM_URL} | tar -xzf - -C /tmp
  
  # Mover binarios
  mv /tmp/prometheus-*/prometheus /usr/local/bin/
  mv /tmp/prometheus-*/promtool /usr/local/bin/
  chown prometheus:prometheus /usr/local/bin/prometheus
  chown prometheus:prometheus /usr/local/bin/promtool

  # Configurar directorios
  mkdir -p /etc/prometheus
  mkdir -p /var/lib/prometheus
  
  mv /tmp/prometheus-*/consoles /etc/prometheus
  mv /tmp/prometheus-*/console_libraries /etc/prometheus
  
  # Configuración básica de Prometheus para leer Unpoller
  cat <<EOF > /etc/prometheus/prometheus.yml
global:
  scrape_interval: 30s
scrape_configs:
  - job_name: 'unpoller'
    static_configs:
      - targets: ['localhost:9130']
EOF

  # Asignar permisos
  chown -R prometheus:prometheus /etc/prometheus
  chown -R prometheus:prometheus /var/lib/prometheus

  # Crear servicio Systemd
  cat <<EOF > /etc/systemd/system/prometheus.service
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
EOF
  
  $STD systemctl daemon-reload
  $STD systemctl enable --now prometheus
  msg_ok "Prometheus installed and configured"

  # Install Unpoller using the official script
  msg_info "Installing Unpoller"
  curl -sL https://golift.io/repo.sh | bash -s - unpoller
  msg_ok "Unpoller installed"
  
  # Configure Unpoller
  msg_info "Configuring Unpoller"
  # Nota: Se ha deshabilitado InfluxDB y habilitado Prometheus
  cat <<EOF > /etc/unpoller/up.conf
[influxdb]
disable = true

[prometheus]
disable = false
http_listen = "0.0.0.0:9130"
report_errors = true

[unifi.defaults]
url = "https://192.168.1.10"   # IMPORTANTE: Cambia esto a la IP de tu CloudKey/Controller
user = "unifipoller"
pass = "CAMBIAME_PASSWORD"     # IMPORTANTE: Pon aquí tu contraseña real
sites = ["all"]
verify_ssl = false
save_ids = true
EOF
  
  $STD systemctl restart unpoller
  msg_ok "Unpoller configured"
  
  # Cleanup
  rm -rf /tmp/prometheus-*
  $STD apt-get autoremove -y
  $STD apt-get clean
}

start
build_container
description

msg_info "Installing Unpoller (Prometheus Edition)..."
pct_exec "install_stack"
msg_ok "Completed Successfully!"

echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${GN}Please edit /etc/unpoller/up.conf inside the container to match your UniFi Controller settings.${CL}"
echo -e "${INFO}${YW} Access services using the following URLs:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Prometheus: http://${IP}:9090${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Unpoller Metrics: http://${IP}:9130/metrics${CL}"
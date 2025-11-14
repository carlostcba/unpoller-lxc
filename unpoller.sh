#!/usr/bin/env bash

# Colores para los mensajes
GREEN="\e[32m"
YELLOW="\e[33m"
RESET="\e[0m"

msg_info() { echo -e "${YELLOW}INFO: $1${RESET}"; }
msg_ok() { echo -e "${GREEN}OK: $1${RESET}"; }
msg_err() { echo -e "\e[31mERROR: $1${RESET}"; }

# --- 1. Verificación de Root ---
if [ "$(id -u)" -ne 0 ]; then
   msg_err "Este script debe ejecutarse como root (o con sudo)."
   exit 1
fi

# --- 2. Instalación de Dependencias ---
msg_info "Actualizando e instalando dependencias (curl, wget, gnupg)..."
apt-get update
apt-get install -y curl wget gnupg apt-transport-https
msg_ok "Dependencias instaladas."

# --- 3. Instalación de Prometheus ---
msg_info "Instalando Prometheus..."
# Crear usuario 'prometheus' para seguridad
useradd --no-create-home --shell /bin/false prometheus || true

# Obtener última versión
LATEST_PROM=$(curl -sL https://api.github.com/repos/prometheus/prometheus/releases/latest | grep '"tag_name":' | sed -E 's/.*"v(.*)",/\1/')
PROM_URL="https://github.com/prometheus/prometheus/releases/download/v${LATEST_PROM}/prometheus-${LATEST_PROM}.linux-amd64.tar.gz"

msg_info "Descargando Prometheus v${LATEST_PROM}..."
wget -qO- ${PROM_URL} | tar -xzf - -C /tmp

# Mover binarios
mv /tmp/prometheus-*/prometheus /usr/local/bin/
mv /tmp/prometheus-*/promtool /usr/local/bin/
chown prometheus:prometheus /usr/local/bin/prometheus
chown prometheus:prometheus /usr/local/bin/promtool

# Crear directorios y mover archivos de configuración
mkdir -p /etc/prometheus
mkdir -p /var/lib/prometheus
mv /tmp/prometheus-*/consoles /etc/prometheus
mv /tmp/prometheus-*/console_libraries /etc/prometheus
chown -R prometheus:prometheus /etc/prometheus
chown -R prometheus:prometheus /var/lib/prometheus

# Crear archivo de configuración de Prometheus
cat <<EOF > /etc/prometheus/prometheus.yml
global:
  scrape_interval: 30s
scrape_configs:
  - job_name: 'unpoller'
    static_configs:
      - targets: ['localhost:9130']
EOF

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

# Activar e iniciar Prometheus
systemctl daemon-reload
systemctl enable --now prometheus
msg_ok "Prometheus instalado y corriendo."

# --- 4. Instalación de Unpoller ---
msg_info "Instalando Unpoller..."
# Usamos el script oficial de GoLift
curl -sL https://golift.io/repo.sh | bash -s - unpoller
msg_ok "Unpoller instalado."

# --- 5. Configuración de Unpoller ---
msg_info "Configurando Unpoller para Prometheus..."
# Crear el archivo de configuración deshabilitando influxdb
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
pass = "@LaSalle2599"     # IMPORTANTE: Pon aquí tu contraseña real
sites = ["all"]
verify_ssl = false
save_ids = true
EOF

# Reiniciar Unpoller para aplicar la configuración
systemctl restart unpoller
msg_ok "Unpoller configurado y reiniciado."

# --- 6. Limpieza ---
msg_info "Limpiando archivos temporales..."
rm -rf /tmp/prometheus-*
apt-get autoremove -y > /dev/null
apt-get clean > /dev/null
msg_ok "Instalación completada."

# --- 7. Mensaje Final ---
echo -e "\n--- ${GREEN}Instalación Finalizada${RESET} ---"
echo -e "Servicios corriendo en esta máquina:"
echo -e "  ${GREEN}Prometheus:${RESET} http://$(curl -s ifconfig.me):9090"
echo -e "  ${GREEN}Unpoller:${RESET}   http://$(curl -s ifconfig.me):9130/metrics"
echo -e "\n${YELLOW}¡ACCIÓN REQUERIDA!${RESET}"
echo -e "Debes editar el archivo ${GREEN}/etc/unpoller/up.conf${RESET} con los datos de tu UniFi Controller."
echo -e "Después de editar, ejecuta: ${GREEN}systemctl restart unpoller${RESET}"
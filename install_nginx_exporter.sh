#!/bin/bash

set -e

EXPORTER_BIN="/usr/local/bin/nginx-prometheus-exporter"
EXPORTER_VERSION="1.1.0"
NGINX_STATUS_PORT=9145
SCRAPE_URI="http://127.0.0.1:${NGINX_STATUS_PORT}/nginx_status"

# Перевіряємо, чи вже встановлено
if [ -f "$EXPORTER_BIN" ]; then
    echo "ℹ️ Nginx Prometheus Exporter вже встановлений у $EXPORTER_BIN."
    echo "⛔ Завершення скрипта."
    exit 0
fi

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    DOWNLOAD_URL="https://github.com/nginx/nginx-prometheus-exporter/releases/download/v${EXPORTER_VERSION}/nginx-prometheus-exporter_${EXPORTER_VERSION}_linux_amd64.tar.gz"
elif [[ "$ARCH" == "aarch64" ]]; then
    DOWNLOAD_URL="https://github.com/nginx/nginx-prometheus-exporter/releases/download/v${EXPORTER_VERSION}/nginx-prometheus-exporter_${EXPORTER_VERSION}_linux_arm64.tar.gz"
else
    echo "❌ Невідома архітектура: $ARCH"
    exit 1
fi

echo "✅ Визначено архітектуру: $ARCH"
echo "📥 Завантажуємо Nginx Exporter з: $DOWNLOAD_URL"

# Завантаження та розпакування
cd /tmp
wget -q "$DOWNLOAD_URL" -O nginx_exporter.tar.gz
mkdir -p /tmp/nginx_exporter_unpack
tar -xvzf nginx_exporter.tar.gz -C /tmp/nginx_exporter_unpack --strip-components=1
cd /tmp/nginx_exporter_unpack

# Копіюємо бінарник
sudo cp nginx-prometheus-exporter "$EXPORTER_BIN"
sudo chmod +x "$EXPORTER_BIN"

# Створюємо системного користувача
if ! id "nginx_exporter" &>/dev/null; then
    sudo useradd --no-create-home --shell /usr/sbin/nologin nginx_exporter
    echo "✅ Користувач nginx_exporter створений"
else
    echo "ℹ️ Користувач nginx_exporter вже існує"
fi

# Додаємо nginx status endpoint
NGINX_CONF="/etc/nginx/conf.d/nginx_status_exporter.conf"
if [ ! -f "$NGINX_CONF" ]; then
    echo "🛠️ Додаємо статус-ендпоінт до nginx на порт ${NGINX_STATUS_PORT}"
    sudo tee "$NGINX_CONF" > /dev/null <<EOF
server {
    listen 127.0.0.1:${NGINX_STATUS_PORT};
    server_name localhost;

    location /nginx_status {
        stub_status;
        allow 127.0.0.1;
        deny all;
    }
}
EOF
    sudo nginx -t && sudo systemctl reload nginx
else
    echo "ℹ️ Конфіг nginx_status вже існує: $NGINX_CONF"
fi

# Створюємо systemd-сервіс
sudo tee /etc/systemd/system/nginx_exporter.service > /dev/null <<EOF
[Unit]
Description=Nginx Prometheus Exporter
After=network.target

[Service]
User=nginx_exporter
Group=nginx_exporter
Type=simple
ExecStart=$EXPORTER_BIN -nginx.scrape-uri $SCRAPE_URI

[Install]
WantedBy=multi-user.target
EOF

echo "⚙️  Сервіс nginx_exporter створений"

# Перезапуск systemd і запуск
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable nginx_exporter
sudo systemctl start nginx_exporter

echo "🚀 Nginx Exporter успішно встановлений і запущений!"

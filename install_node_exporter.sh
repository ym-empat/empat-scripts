#!/bin/bash

set -e

# Перевіряємо чи вже встановлений node_exporter
if command -v /usr/local/bin/node_exporter &>/dev/null; then
    echo "ℹ️ Node Exporter вже встановлений у /usr/local/bin/node_exporter."
    echo "⛔ Завершення скрипта."
    exit 0
fi

# Визначаємо архітектуру
ARCH=$(uname -m)

if [[ "$ARCH" == "x86_64" ]]; then
    DOWNLOAD_URL="https://github.com/prometheus/node_exporter/releases/download/v1.9.1/node_exporter-1.9.1.linux-amd64.tar.gz"
elif [[ "$ARCH" == "aarch64" ]]; then
    DOWNLOAD_URL="https://github.com/prometheus/node_exporter/releases/download/v1.9.1/node_exporter-1.9.1.linux-arm64.tar.gz"
else
    echo "❌ Невідома архітектура: $ARCH"
    exit 1
fi

echo "✅ Визначено архітектуру: $ARCH"
echo "📥 Завантажуємо Node Exporter з: $DOWNLOAD_URL"

# Завантаження і встановлення
cd /tmp
wget -q "$DOWNLOAD_URL" -O node_exporter.tar.gz
tar xvfz node_exporter.tar.gz
cd node_exporter-*

# Копіюємо бінарник
sudo cp node_exporter /usr/local/bin/
sudo chmod +x /usr/local/bin/node_exporter

# Створюємо системного користувача, якщо ще немає
if ! id "node_exporter" &>/dev/null; then
    sudo useradd --no-create-home --shell /usr/sbin/nologin node_exporter
    echo "✅ Користувач node_exporter створений"
else
    echo "ℹ️ Користувач node_exporter вже існує"
fi

# Створюємо systemd-сервіс
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=default.target
EOF

echo "⚙️  Сервіс node_exporter створений"

# Перезапускаємо systemd і запускаємо сервіс
sudo systemctl daemon-reexec
sudo systemctl enable node_exporter
sudo systemctl start node_exporter

echo "🚀 Node Exporter успішно встановлений і запущений!"

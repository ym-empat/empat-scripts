#!/bin/bash

set -e

# Перевіряємо чи вже встановлений mysqld_exporter
if command -v /usr/local/bin/mysqld_exporter &>/dev/null; then
    echo "ℹ️ mysqld_exporter вже встановлений у /usr/local/bin/mysqld_exporter."
    echo "⛔ Завершення скрипта."
    exit 0
fi

# Визначаємо архітектуру
ARCH=$(uname -m)

if [[ "$ARCH" == "x86_64" ]]; then
    DOWNLOAD_URL="https://github.com/prometheus/mysqld_exporter/releases/download/v0.17.2/mysqld_exporter-0.17.2.linux-amd64.tar.gz"
elif [[ "$ARCH" == "aarch64" ]]; then
    DOWNLOAD_URL="https://github.com/prometheus/mysqld_exporter/releases/download/v0.17.2/mysqld_exporter-0.17.2.linux-arm64.tar.gz"
else
    echo "❌ Невідома архітектура: $ARCH"
    exit 1
fi

echo "✅ Визначено архітектуру: $ARCH"
echo "📥 Завантажуємо mysqld_exporter з: $DOWNLOAD_URL"

# Завантаження і встановлення
cd /tmp
wget -q "$DOWNLOAD_URL" -O mysqld_exporter.tar.gz
tar xvfz mysqld_exporter.tar.gz
cd mysqld_exporter-*

# Копіюємо бінарник
sudo cp mysqld_exporter /usr/local/bin/
sudo chmod +x /usr/local/bin/mysqld_exporter

# Створюємо системного користувача, якщо ще немає
if ! id "mysqld_exporter" &>/dev/null; then
    sudo useradd --no-create-home --shell /usr/sbin/nologin mysqld_exporter
    echo "✅ Користувач mysqld_exporter створений"
else
    echo "ℹ️ Користувач mysqld_exporter вже існує"
fi

# Створюємо MySQL юзера, якщо ще не існує
echo "👤 Створюємо користувача 'exporter' в MySQL (якщо ще немає)..."
sudo mysql <<EOF
CREATE USER IF NOT EXISTS 'exporter'@'localhost' IDENTIFIED BY '9pEhZYPaiNGVRUbRLG';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';
FLUSH PRIVILEGES;
EOF
echo "✅ MySQL користувач 'exporter' створений або вже існує"

# Створюємо credentials файл
MYSQL_EXPORTER_CNF="/etc/.mysqld_exporter.cnf"

if [ ! -f "$MYSQL_EXPORTER_CNF" ]; then
    echo "🔐 Створюємо файл з MySQL креденшалами: $MYSQL_EXPORTER_CNF"
    sudo tee "$MYSQL_EXPORTER_CNF" > /dev/null <<EOF
[client]
user=exporter
password=9pEhZYPaiNGVRUbRLG
host=localhost
EOF
    sudo chown mysqld_exporter:mysqld_exporter "$MYSQL_EXPORTER_CNF"
    sudo chmod 600 "$MYSQL_EXPORTER_CNF"
else
    echo "ℹ️ Файл з креденшалами вже існує: $MYSQL_EXPORTER_CNF"
fi

# Створюємо systemd-сервіс
sudo tee /etc/systemd/system/mysqld_exporter.service > /dev/null <<EOF
[Unit]
Description=mysqld_exporter
After=network.target

[Service]
User=mysqld_exporter
Group=mysqld_exporter
Type=simple
ExecStart=/usr/local/bin/mysqld_exporter \\
  --config.my-cnf=$MYSQL_EXPORTER_CNF \\
  --web.listen-address=":9104"

[Install]
WantedBy=multi-user.target
EOF

echo "⚙️  Сервіс mysqld_exporter створений"

# Перезапускаємо systemd і запускаємо сервіс
sudo systemctl daemon-reexec
sudo systemctl enable mysqld_exporter
sudo systemctl start mysqld_exporter

echo "🚀 mysqld_exporter успішно встановлений і запущений на порті 9104!"

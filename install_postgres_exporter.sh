#!/bin/bash

set -e

# Перевіряємо чи вже встановлений postgres_exporter
if command -v /usr/local/bin/postgres_exporter &>/dev/null; then
    echo "ℹ️ postgres_exporter вже встановлений у /usr/local/bin/postgres_exporter."
    echo "⛔ Завершення скрипта."
    exit 0
fi

# Визначаємо архітектуру
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    DOWNLOAD_URL="https://github.com/prometheus-community/postgres_exporter/releases/download/v0.17.1/postgres_exporter-0.17.1.linux-amd64.tar.gz"
elif [[ "$ARCH" == "aarch64" ]]; then
    DOWNLOAD_URL="https://github.com/prometheus-community/postgres_exporter/releases/download/v0.17.1/postgres_exporter-0.17.1.linux-arm64.tar.gz"
else
    echo "❌ Невідома архітектура: $ARCH"
    exit 1
fi

echo "✅ Визначено архітектуру: $ARCH"
echo "📥 Завантажуємо postgres_exporter з: $DOWNLOAD_URL"

cd /tmp
wget -q "$DOWNLOAD_URL" -O postgres_exporter.tar.gz
tar xvfz postgres_exporter.tar.gz
cd postgres_exporter-*

# Копіюємо бінарник
sudo cp postgres_exporter /usr/local/bin/
sudo chmod +x /usr/local/bin/postgres_exporter

# Створюємо системного користувача, якщо ще немає
if ! id "postgres_exporter" &>/dev/null; then
    sudo useradd --no-create-home --shell /usr/sbin/nologin postgres_exporter
    echo "✅ Користувач postgres_exporter створений"
else
    echo "ℹ️ Користувач postgres_exporter вже існує"
fi

# Створюємо PostgreSQL користувача
echo "👤 Створюємо PostgreSQL користувача 'exporter' з мінімальними правами..."
sudo -u postgres psql <<EOF
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'exporter') THEN
      CREATE ROLE exporter LOGIN PASSWORD '9pEhZYPaiNGVRUbRLG';
   END IF;
END
\$\$;

GRANT CONNECT ON DATABASE postgres TO exporter;
GRANT USAGE ON SCHEMA public TO exporter;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO exporter;
GRANT pg_monitor TO exporter;
EOF
echo "✅ PostgreSQL користувач 'exporter' створений або вже існує."

# Створюємо .pgpass файл
PGPASS_FILE="/etc/postgres_exporter.pgpass"
echo "localhost:5432:postgres:exporter:9pEhZYPaiNGVRUbRLG" | sudo tee "$PGPASS_FILE" > /dev/null
sudo chown postgres_exporter:postgres_exporter "$PGPASS_FILE"
sudo chmod 600 "$PGPASS_FILE"
echo "🔐 Файл з креденшалами створений: $PGPASS_FILE"

# Створюємо systemd-сервіс
sudo tee /etc/systemd/system/postgres_exporter.service > /dev/null <<EOF
[Unit]
Description=PostgreSQL Exporter
After=network.target

[Service]
User=postgres_exporter
Group=postgres_exporter
Environment=DATA_SOURCE_NAME=postgresql://exporter:9pEhZYPaiNGVRUbRLG@localhost:5432/postgres?sslmode=disable
Environment=PGPASSFILE=$PGPASS_FILE
ExecStart=/usr/local/bin/postgres_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "⚙️  Сервіс postgres_exporter створений"

# Перезапускаємо systemd і запускаємо сервіс
sudo systemctl daemon-reexec
sudo systemctl enable postgres_exporter
sudo systemctl start postgres_exporter

echo "🚀 postgres_exporter успішно встановлений і запущений на порті 9187!"

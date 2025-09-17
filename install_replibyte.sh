#!/usr/bin/env bash
set -euo pipefail

# === Config ===
INSTALL_DIR="/usr/local/bin"
BIN_NAME="replibyte"
ARM_URL="https://empat-public.s3.eu-central-1.amazonaws.com/replibyte-exec-arm"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "❌ Потрібна утиліта '$1'"; exit 1; }
}

# Basic deps (jq/tar/wget не потрібні для ARM-гілки, але перевіримо перед x86)
need_cmd uname
need_cmd curl

arch="$(uname -m | tr '[:upper:]' '[:lower:]')"
os="$(uname -s | tr '[:upper:]' '[:lower:]')"

is_arm=false
case "$arch" in
  arm*|aarch64) is_arm=true ;;
esac

echo "➡️  Виявлена платформа: $os $arch"

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

install_to_path() {
  local src="$1"
  local dest="$INSTALL_DIR/$BIN_NAME"
  echo "🔧 Роблю виконуваним та переміщую до $dest ..."
  chmod +x "$src"
  # Використай sudo, якщо потрібно
  if [ -w "$INSTALL_DIR" ]; then
    mv "$src" "$dest"
  else
    sudo mv "$src" "$dest"
  fi
  echo "✅ Встановлено: $(command -v "$BIN_NAME")"
  "$dest" --version || true
}

if $is_arm; then
  echo "🐹 ARM-архітектура виявлена — використовую попередньо зібраний бінарник."
  cd "$tmpdir"
  out="$BIN_NAME"
  echo "⬇️  Завантажую $ARM_URL ..."
  curl -fsSL "$ARM_URL" -o "$out"
  install_to_path "$out"
  exit 0
fi

echo "🖥️  Не-ARM архітектура — завантажую останній реліз з GitHub."
need_cmd jq
need_cmd wget
need_cmd tar
cd "$tmpdir"

# Отримуємо URL саме до linux-musl архіву (x86_64/amd64)
echo "🌐 Отримую список asset'ів останнього релізу..."
asset_url="$(
  curl -fsSL https://api.github.com/repos/Qovery/replibyte/releases/latest \
  | jq -r '.assets[].browser_download_url' \
  | grep -i 'linux-musl\.tar\.gz$' \
  | grep -Ei '(x86_64|amd64)' \
  | head -n1
)"

if [ -z "${asset_url:-}" ]; then
  echo "❌ Не вдалося знайти linux-musl x86_64 архів у останньому релізі."
  echo "Сирий список asset'ів:"
  curl -fsSL https://api.github.com/repos/Qovery/replibyte/releases/latest | jq -r '.assets[].browser_download_url'
  exit 1
fi

echo "⬇️  Завантажую: $asset_url"
wget -q "$asset_url"

archive="$(basename "$asset_url")"
echo "📦 Розпаковую $archive ..."
tar zxf "$archive"

# Знаходимо виконуваний файл "replibyte" після розпаковки
candidate=""
if [ -f "$BIN_NAME" ]; then
  candidate="$BIN_NAME"
else
  # шукаємо у вкладених директоріях
  candidate="$(find . -type f -name "$BIN_NAME" -perm -u+x -print -quit || true)"
  # якщо не позначено як виконуваний — все одно візьмемо перший збіг
  if [ -z "$candidate" ]; then
    candidate="$(find . -type f -name "$BIN_NAME" -print -quit || true)"
  fi
fi

if [ -z "$candidate" ]; then
  echo "❌ Після розпаковки не знайшов файл '$BIN_NAME'."
  find . -maxdepth 2 -type f | sed 's/^/ • /'
  exit 1
fi

install_to_path "$candidate"

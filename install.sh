#!/bin/bash
# =============================================================
# Тувинско-русский переводчик — установка
# =============================================================
set -e

APP_DIR="/opt/translator"
MODEL_DIR="$APP_DIR/model"
MODEL_REPO="Agisight/translategemma-tyvan-4b"

echo "╔══════════════════════════════════════════════════╗"
echo "║  Тувинско-русский переводчик                     ║"
echo "║  TranslateGemma 4B + Agisight/tyv-rus-200k       ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── 1. Системные пакеты ──────────────────────────────────────
echo "→ [1/5] Системные пакеты..."
apt update -qq
apt install -y -qq python3-pip python3-venv git curl > /dev/null 2>&1
echo "  ✓ Готово"

# ── 2. Python окружение ──────────────────────────────────────
echo "→ [2/5] Python окружение..."
mkdir -p "$APP_DIR"
if [ ! -d "$APP_DIR/venv" ]; then
    python3 -m venv "$APP_DIR/venv"
fi
source "$APP_DIR/venv/bin/activate"
pip install -q fastapi uvicorn aiosqlite transformers torch accelerate sentencepiece huggingface_hub
echo "  ✓ Готово"

# ── 3. Модель ────────────────────────────────────────────────
echo "→ [3/5] Модель..."
if [ -f "$MODEL_DIR/config.json" ]; then
    SIZE=$(du -sh "$MODEL_DIR" 2>/dev/null | cut -f1)
    echo ""
    echo "  Модель уже скачана ($SIZE)"
    echo ""
    echo "  1) Использовать текущую модель"
    echo "  2) Удалить и скачать заново с HuggingFace"
    echo ""
    read -p "  Выберите (1/2) [1]: " choice
    choice=${choice:-1}

    if [ "$choice" = "2" ]; then
        echo "  → Удаляем старую модель..."
        rm -rf "$MODEL_DIR"
        echo "  → Скачиваем новую из $MODEL_REPO..."
        python3 -c "
from huggingface_hub import snapshot_download
snapshot_download('$MODEL_REPO', local_dir='$MODEL_DIR')
"
        echo "  ✓ Модель скачана"
    else
        echo "  ✓ Используем текущую модель"
    fi
else
    echo "  Модель не найдена, скачиваем из $MODEL_REPO..."
    python3 -c "
from huggingface_hub import snapshot_download
snapshot_download('$MODEL_REPO', local_dir='$MODEL_DIR')
"
    echo "  ✓ Модель скачана"
fi

# ── 4. server.py ─────────────────────────────────────────────
echo "→ [4/5] server.py..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/server.py" ]; then
    cp "$SCRIPT_DIR/server.py" "$APP_DIR/server.py"
    echo "  ✓ Скопирован"
elif [ -f "$APP_DIR/server.py" ]; then
    echo "  ✓ Уже на месте"
else
    echo "  ✗ server.py не найден!"
    exit 1
fi

# ── 5. DNS + Systemd ─────────────────────────────────────────
echo "→ [5/5] DNS и systemd сервис..."
grep -q "nameserver" /etc/resolv.conf 2>/dev/null || echo "nameserver 8.8.8.8" > /etc/resolv.conf

cat > /etc/systemd/system/tyvan-translator.service << EOF
[Unit]
Description=Tuvan-Russian Translator API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/venv/bin/uvicorn server:app --host 0.0.0.0 --port 8000 --workers 1
Restart=always
RestartSec=10
MemoryMax=8G
MemoryHigh=7G

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tyvan-translator
echo "  ✓ Готово"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  Установка завершена!                            ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║                                                  ║"
echo "║  Проверка:  bash check.sh                        ║"
echo "║  Запуск:    systemctl start tyvan-translator     ║"
echo "║  Удаление:  bash uninstall.sh                    ║"
echo "║                                                  ║"
echo "╚══════════════════════════════════════════════════╝"

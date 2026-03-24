#!/bin/bash
# =============================================================
# Установка на сервер (контейнер 104)
# Учитывает что модель уже скачана в /opt/translator/model
# =============================================================
set -e

APP_DIR="/opt/translator"

echo "=== Проверка сервера ==="

# 1. Проверяем модель
if [ -f "$APP_DIR/model/config.json" ]; then
    echo "✓ Модель найдена"
else
    echo "✗ Модель не найдена в $APP_DIR/model/"
    echo "  Скачайте: python3 -c \"from huggingface_hub import snapshot_download; snapshot_download('Agisight/translategemma-tyvan-4b', local_dir='$APP_DIR/model')\""
    exit 1
fi

# 2. Проверяем venv
if [ -d "$APP_DIR/venv" ]; then
    echo "✓ Python venv найден"
else
    echo "→ Создаём venv..."
    python3 -m venv "$APP_DIR/venv"
fi

source "$APP_DIR/venv/bin/activate"

# 3. Доставляем пакеты
echo "→ Проверяем Python пакеты..."
pip install -q fastapi uvicorn aiosqlite transformers torch accelerate sentencepiece huggingface_hub 2>/dev/null
echo "✓ Пакеты установлены"

# 4. Копируем server.py
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/server.py" ]; then
    cp "$SCRIPT_DIR/server.py" "$APP_DIR/server.py"
    echo "✓ server.py скопирован"
fi

# 5. DNS
grep -q "nameserver" /etc/resolv.conf 2>/dev/null || echo "nameserver 8.8.8.8" > /etc/resolv.conf

# 6. Systemd сервис с лимитом памяти
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
echo "✓ Systemd сервис создан"

echo ""
echo "=== Готово! ==="
echo ""
echo "  Запуск:  cd $APP_DIR && source venv/bin/activate && uvicorn server:app --host 0.0.0.0 --port 8000"
echo "  Сервис:  systemctl start tyvan-translator"
echo "  Тест:    curl -X POST http://localhost:8000/translate -H 'Content-Type: application/json' -d '{\"text\":\"Экии!\",\"direction\":\"tyv-ru\"}'"
echo ""

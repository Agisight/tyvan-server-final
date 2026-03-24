#!/bin/bash
# Удаление переводчика
APP_DIR="/opt/translator"

echo "⚠  Будет удалено:"
echo "   - Модель (~8 GB)"
echo "   - Python окружение"
echo "   - База переводов"
echo "   - Systemd сервис"
echo ""
read -p "Уверены? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Отменено"
    exit 0
fi

echo "→ Останавливаем сервис..."
systemctl stop tyvan-translator 2>/dev/null || true
systemctl disable tyvan-translator 2>/dev/null || true
rm -f /etc/systemd/system/tyvan-translator.service
systemctl daemon-reload

echo "→ Удаляем файлы..."
rm -rf "$APP_DIR/venv"
rm -rf "$APP_DIR/model"
rm -rf "$APP_DIR/llama.cpp"
rm -rf "$APP_DIR/setup"
rm -f "$APP_DIR/translations.db"
rm -f "$APP_DIR/server.py"
rm -f "$APP_DIR/*.sh"

echo ""
echo "✓ Удалено"

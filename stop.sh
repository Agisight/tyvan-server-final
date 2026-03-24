#!/bin/bash
# Остановка переводчика
echo "Останавливаем..."
systemctl stop tyvan-translator 2>/dev/null
pkill -f "uvicorn server:app" 2>/dev/null
echo "✓ Остановлен"

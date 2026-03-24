#!/bin/bash
# Запуск переводчика
cd /opt/translator
source venv/bin/activate
echo "Запуск на http://0.0.0.0:8000"
echo "Загрузка модели ~1-2 минуты..."
uvicorn server:app --host 0.0.0.0 --port 8000 --workers 1

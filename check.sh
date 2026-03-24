#!/bin/bash
# =============================================================
# Проверка что всё на месте перед запуском
# =============================================================

APP_DIR="/opt/translator"
ERRORS=0

echo "=== Проверка перед запуском ==="
echo ""

# 1. Модель
echo -n "[1] Модель: "
if [ -f "$APP_DIR/model/config.json" ]; then
    SIZE=$(du -sh "$APP_DIR/model" 2>/dev/null | cut -f1)
    echo "✓ ($SIZE)"
else
    echo "✗ Не найдена в $APP_DIR/model/"
    ERRORS=$((ERRORS+1))
fi

# 2. Venv
echo -n "[2] Python venv: "
if [ -f "$APP_DIR/venv/bin/python3" ]; then
    echo "✓"
else
    echo "✗ Не найден"
    ERRORS=$((ERRORS+1))
fi

# 3. Пакеты
echo -n "[3] Пакеты: "
MISSING=""
for pkg in fastapi uvicorn aiosqlite transformers torch; do
    $APP_DIR/venv/bin/python3 -c "import $pkg" 2>/dev/null || MISSING="$MISSING $pkg"
done
if [ -z "$MISSING" ]; then
    echo "✓"
else
    echo "✗ Не хватает:$MISSING"
    ERRORS=$((ERRORS+1))
fi

# 4. server.py
echo -n "[4] server.py: "
if [ -f "$APP_DIR/server.py" ]; then
    echo "✓"
else
    echo "✗ Не найден"
    ERRORS=$((ERRORS+1))
fi

# 5. RAM
echo -n "[5] RAM: "
TOTAL_MB=$(free -m | awk '/Mem:/ {print $2}')
FREE_MB=$(free -m | awk '/Mem:/ {print $7}')
echo "${FREE_MB}MB свободно из ${TOTAL_MB}MB"
if [ "$FREE_MB" -lt 8500 ]; then
    echo "    ⚠ Может не хватить (нужно ~8.5 GB для модели)"
    ERRORS=$((ERRORS+1))
fi

# 6. Диск
echo -n "[6] Диск: "
FREE_DISK=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
echo "${FREE_DISK}GB свободно"

# 7. DNS
echo -n "[7] DNS: "
if ping -c 1 -W 2 google.com > /dev/null 2>&1; then
    echo "✓"
else
    echo "✗ Нет интернета"
    ERRORS=$((ERRORS+1))
fi

# 8. Порт 8000
echo -n "[8] Порт 8000: "
if ss -tlnp | grep -q ":8000 "; then
    echo "⚠ Уже занят!"
else
    echo "✓ Свободен"
fi

echo ""
if [ "$ERRORS" -eq 0 ]; then
    echo "=== Всё готово! Запускайте: ==="
    echo "  cd $APP_DIR && source venv/bin/activate && uvicorn server:app --host 0.0.0.0 --port 8000"
else
    echo "=== Найдено проблем: $ERRORS ==="
fi

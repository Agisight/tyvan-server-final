#!/bin/bash
# Тест переводчика
echo "=== Тест переводчика ==="
echo ""

if ! curl -s http://localhost:8000/health > /dev/null 2>&1; then
    echo "✗ Сервер не запущен"
    echo "  Запустите: systemctl start tyvan-translator"
    echo "  Или:       bash start.sh"
    exit 1
fi
echo "✓ Сервер работает"
echo ""

echo "--- Тувинский → Русский ---"
for text in "Экии!" "Мен Тывада чурттап турар мен." "Четтирдим, эки-дир." "Байырлыг!"; do
    result=$(curl -s -X POST http://localhost:8000/translate \
        -H "Content-Type: application/json" \
        -d "{\"text\":\"$text\",\"direction\":\"tyv-ru\"}")
    translation=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin)['variants'][0]['translation'])" 2>/dev/null)
    ms=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin)['time_ms'])" 2>/dev/null)
    echo "  tyv: $text"
    echo "  rus: $translation  (${ms}ms)"
    echo ""
done

echo "--- Русский → Тувинский ---"
for text in "Привет!" "Как вас зовут?" "Спасибо!" "До свидания!"; do
    result=$(curl -s -X POST http://localhost:8000/translate \
        -H "Content-Type: application/json" \
        -d "{\"text\":\"$text\",\"direction\":\"ru-tyv\"}")
    translation=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin)['variants'][0]['translation'])" 2>/dev/null)
    ms=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin)['time_ms'])" 2>/dev/null)
    echo "  rus: $text"
    echo "  tyv: $translation  (${ms}ms)"
    echo ""
done

echo "--- Статистика ---"
curl -s http://localhost:8000/stats | python3 -m json.tool

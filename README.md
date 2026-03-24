# Тувинско-русский переводчик

ИИ-переводчик на базе TranslateGemma 4B, дообученной на [Agisight/tyv-rus-200k](https://huggingface.co/datasets/Agisight/tyv-rus-200k) (296K пар).

## Установка
```bash
cd /opt/translator
git clone https://github.com/Agisight/tyvan-server-final.git setup
cp setup/server.py . && cp setup/*.sh . && chmod +x *.sh
bash check.sh      # Проверка
bash install.sh    # Установка
```

## API
```bash
# Перевод
curl -X POST http://localhost:8000/translate \
  -H "Content-Type: application/json" \
  -d '{"text": "Экии!", "direction": "tyv-ru"}'

# Несколько вариантов
curl -X POST http://localhost:8000/translate \
  -d '{"text": "Экии!", "direction": "tyv-ru", "num_variants": 5}'

# Голосование
curl -X POST http://localhost:8000/vote \
  -d '{"translation_id": 1, "vote": 1}'
```

## Управление
```bash
systemctl start tyvan-translator    # Запуск
systemctl stop tyvan-translator     # Остановка
systemctl status tyvan-translator   # Статус
bash uninstall.sh                   # Удаление
```

## Автор

Ali Kuzhuget — [tyvan.ru](https://tyvan.ru)


После этого на сервере (контейнер 104):
```
cd /opt/translator
git clone https://github.com/Agisight/tyvan-server-final.git setup
cp setup/server.py . && cp setup/*.sh . && chmod +x *.sh
bash check.sh
```

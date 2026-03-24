# Тувинско-русский переводчик

ИИ-переводчик на базе TranslateGemma 4B, дообученной на [Agisight/tyv-rus-200k](https://huggingface.co/datasets/Agisight/tyv-rus-200k) (296K пар).

## Установка

```bash
cd /opt/translator
git clone https://github.com/Agisight/tyvan-server-final.git setup
cp setup/server.py . && cp setup/*.sh . && chmod +x *.sh
bash check.sh       # Проверка
bash install.sh     # Установка
```

## Запуск / Остановка

```bash
systemctl start tyvan-translator     # Запуск как сервис
systemctl stop tyvan-translator      # Остановка
systemctl status tyvan-translator    # Статус

# Или вручную:
bash start.sh       # Запуск в терминале
bash stop.sh        # Остановка
```

## Тест

```bash
bash test.sh
```

## API

```bash
# Перевод
curl -X POST http://localhost:8000/translate \
  -H "Content-Type: application/json" \
  -d '{"text": "Экии!", "direction": "tyv-ru"}'

# Несколько вариантов
curl -X POST http://localhost:8000/translate \
  -H "Content-Type: application/json" \
  -d '{"text": "Экии!", "direction": "tyv-ru", "num_variants": 5}'

# Голосование (+1 / -1)
curl -X POST http://localhost:8000/vote \
  -H "Content-Type: application/json" \
  -d '{"translation_id": 1, "vote": 1}'

# Лучшие переводы по рейтингу
curl http://localhost:8000/top

# Экспорт для ретренировки
curl http://localhost:8000/export/training-data

# Статистика
curl http://localhost:8000/stats
```

## Удаление

```bash
bash uninstall.sh
```

## Требования

- Ubuntu 22.04+ / Debian 12+
- 10+ GB RAM
- 15 GB свободного диска
- Python 3.10+

## Защита памяти

Systemd сервис ограничен 8 GB (MemoryMax). При превышении процесс убивается и перезапускается автоматически. Хост и другие VM не пострадают.

## Автор

Ali Kuzhuget — [tyvan.ru](https://tyvan.ru)

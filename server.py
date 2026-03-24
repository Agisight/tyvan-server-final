"""
Тувинско-русский переводчик — API сервер
Автор: Ali Kuzhuget (tyvan.ru)
"""

import hashlib
import json
import logging
import os
import time
from contextlib import asynccontextmanager

import aiosqlite
import torch
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from transformers import AutoModelForCausalLM, AutoTokenizer

# ── Настройки ─────────────────────────────────────────────────

APP_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(APP_DIR, "model")
DB_PATH = os.path.join(APP_DIR, "translations.db")

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("tyvan")

model = None
tokenizer = None


# ── База данных ───────────────────────────────────────────────

async def init_db():
    async with aiosqlite.connect(DB_PATH) as db:
        await db.executescript("""
            CREATE TABLE IF NOT EXISTS translations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source_hash TEXT NOT NULL,
                source_text TEXT NOT NULL,
                direction TEXT NOT NULL,
                variant_index INTEGER NOT NULL,
                translation TEXT NOT NULL,
                temperature REAL NOT NULL,
                score INTEGER DEFAULT 0,
                upvotes INTEGER DEFAULT 0,
                downvotes INTEGER DEFAULT 0,
                created_at TEXT DEFAULT (datetime('now')),
                UNIQUE(source_hash, direction, variant_index)
            );
            CREATE INDEX IF NOT EXISTS idx_hash ON translations(source_hash, direction);
            CREATE TABLE IF NOT EXISTS request_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source_text TEXT,
                direction TEXT,
                cache_hit INTEGER DEFAULT 0,
                response_ms INTEGER,
                created_at TEXT DEFAULT (datetime('now'))
            );
        """)
        await db.commit()
    log.info(f"БД: {DB_PATH}")


def text_hash(text, direction):
    return hashlib.sha256(f"{direction}:{text.strip().lower()}".encode()).hexdigest()[:16]


# ── Перевод ───────────────────────────────────────────────────

def do_translate(text, src, tgt, temperature=0.1):
    payload = json.dumps([{
        "type": "text",
        "source_lang_code": src,
        "target_lang_code": tgt,
        "text": text.strip()
    }], ensure_ascii=False)

    prompt = f"<start_of_turn>user\n{payload}<end_of_turn>\n<start_of_turn>model\n"
    inputs = tokenizer(prompt, return_tensors="pt")

    with torch.no_grad():
        out = model.generate(
            **inputs,
            max_new_tokens=256,
            temperature=max(temperature, 0.01),
            do_sample=True,
        )

    full = tokenizer.decode(out[0], skip_special_tokens=True)
    if "model\n" in full:
        return full.split("model\n")[-1].strip()
    return full.strip()


def generate_variants(text, src, tgt, num=5):
    temperatures = [0.05]
    for i in range(1, num):
        temperatures.append(0.3 + i * 0.15)

    seen = set()
    variants = []
    for i, temp in enumerate(temperatures[:num]):
        try:
            result = do_translate(text, src, tgt, temperature=temp)
            norm = result.strip().lower()
            if norm not in seen:
                seen.add(norm)
                variants.append({"index": len(variants), "translation": result, "temperature": round(temp, 2)})
        except Exception as e:
            log.error(f"Вариант {i}: {e}")
    return variants


# ── FastAPI ───────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app):
    global model, tokenizer

    # Проверяем что модель существует
    if not os.path.exists(MODEL_PATH):
        log.error(f"Модель не найдена: {MODEL_PATH}")
        log.error("Запустите: bash install.sh")
        raise RuntimeError(f"Model not found: {MODEL_PATH}")

    if not os.path.exists(os.path.join(MODEL_PATH, "config.json")):
        log.error(f"config.json не найден в {MODEL_PATH}")
        raise RuntimeError(f"config.json not found in {MODEL_PATH}")

    log.info(f"Загрузка модели из {MODEL_PATH}...")
    log.info("Это займёт 1-2 минуты...")

    tokenizer = AutoTokenizer.from_pretrained(MODEL_PATH)
    model = AutoModelForCausalLM.from_pretrained(
        MODEL_PATH,
        torch_dtype=torch.bfloat16,  # 8 GB вместо 16 GB в float32
        device_map="cpu",
        low_cpu_mem_usage=True,
    )

    log.info("Модель загружена!")
    await init_db()
    yield
    log.info("Сервер остановлен")


app = FastAPI(title="Тувинско-русский переводчик", version="1.0.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

DIRECTIONS = {"tyv-ru": ("tyv", "ru"), "ru-tyv": ("ru", "tyv")}


class TranslateRequest(BaseModel):
    text: str
    direction: str = "tyv-ru"
    num_variants: int = 1

class VoteRequest(BaseModel):
    translation_id: int
    vote: int


@app.post("/translate")
async def translate(req: TranslateRequest):
    if not req.text.strip():
        raise HTTPException(400, "Пустой текст")
    if req.direction not in DIRECTIONS:
        raise HTTPException(400, f"direction: {list(DIRECTIONS.keys())}")

    num = min(max(req.num_variants, 1), 10)
    src, tgt = DIRECTIONS[req.direction]
    h = text_hash(req.text, req.direction)
    start = time.time()

    # Кеш
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        rows = await (await db.execute(
            "SELECT id,translation,score,upvotes,downvotes,temperature FROM translations WHERE source_hash=? AND direction=? ORDER BY score DESC LIMIT ?",
            (h, req.direction, num)
        )).fetchall()

    if rows:
        ms = int((time.time() - start) * 1000)
        async with aiosqlite.connect(DB_PATH) as db:
            await db.execute("INSERT INTO request_log (source_text,direction,cache_hit,response_ms) VALUES (?,?,1,?)", (req.text, req.direction, ms))
            await db.commit()
        return {"source": req.text, "direction": req.direction, "cached": True, "time_ms": ms, "variants": [dict(r) for r in rows]}

    # Генерируем
    variants = generate_variants(req.text, src, tgt, num)
    if not variants:
        raise HTTPException(500, "Не удалось перевести")

    async with aiosqlite.connect(DB_PATH) as db:
        for v in variants:
            await db.execute(
                "INSERT OR IGNORE INTO translations (source_hash,source_text,direction,variant_index,translation,temperature) VALUES (?,?,?,?,?,?)",
                (h, req.text.strip(), req.direction, v["index"], v["translation"], v["temperature"])
            )
        ms = int((time.time() - start) * 1000)
        await db.execute("INSERT INTO request_log (source_text,direction,cache_hit,response_ms) VALUES (?,?,0,?)", (req.text, req.direction, ms))
        await db.commit()

        db.row_factory = aiosqlite.Row
        rows = await (await db.execute(
            "SELECT id,translation,score,upvotes,downvotes,temperature FROM translations WHERE source_hash=? AND direction=? ORDER BY score DESC LIMIT ?",
            (h, req.direction, num)
        )).fetchall()

    return {"source": req.text, "direction": req.direction, "cached": False, "time_ms": ms, "variants": [dict(r) for r in rows]}


@app.post("/vote")
async def vote(req: VoteRequest):
    if req.vote not in (1, -1):
        raise HTTPException(400, "vote: 1 или -1")
    async with aiosqlite.connect(DB_PATH) as db:
        if req.vote == 1:
            await db.execute("UPDATE translations SET score=score+1, upvotes=upvotes+1 WHERE id=?", (req.translation_id,))
        else:
            await db.execute("UPDATE translations SET score=score-1, downvotes=downvotes+1 WHERE id=?", (req.translation_id,))
        await db.commit()
        db.row_factory = aiosqlite.Row
        row = await (await db.execute("SELECT id,score,upvotes,downvotes FROM translations WHERE id=?", (req.translation_id,))).fetchone()
    if not row:
        raise HTTPException(404, "Не найден")
    return dict(row)


@app.get("/top")
async def top(direction: str = "tyv-ru", limit: int = 100, min_score: int = 1):
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        rows = await (await db.execute(
            "SELECT source_text,translation,score,upvotes,downvotes FROM translations WHERE direction=? AND score>=? ORDER BY score DESC LIMIT ?",
            (direction, min_score, limit)
        )).fetchall()
    return {"direction": direction, "count": len(rows), "translations": [dict(r) for r in rows]}


@app.get("/export/training-data")
async def export_data(min_score: int = 2):
    pairs = []
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        for d in ["tyv-ru", "ru-tyv"]:
            rows = await (await db.execute(
                "SELECT source_text,translation FROM translations WHERE direction=? AND score>=?", (d, min_score)
            )).fetchall()
            for r in rows:
                if d == "tyv-ru":
                    pairs.append({"tyv": r["source_text"], "ru": r["translation"]})
                else:
                    pairs.append({"tyv": r["translation"], "ru": r["source_text"]})
    return {"format": "Agisight/tyv-rus-200k", "count": len(pairs), "pairs": pairs}


@app.get("/stats")
async def stats():
    async with aiosqlite.connect(DB_PATH) as db:
        total = (await (await db.execute("SELECT COUNT(*) FROM translations")).fetchone())[0]
        unique = (await (await db.execute("SELECT COUNT(DISTINCT source_hash) FROM translations")).fetchone())[0]
        rated = (await (await db.execute("SELECT COUNT(*) FROM translations WHERE score!=0")).fetchone())[0]
        reqs = (await (await db.execute("SELECT COUNT(*) FROM request_log")).fetchone())[0]
        hits = (await (await db.execute("SELECT COUNT(*) FROM request_log WHERE cache_hit=1")).fetchone())[0]
    return {
        "cached_translations": total, "unique_texts": unique, "rated": rated,
        "total_requests": reqs, "cache_hit_rate": f"{hits/max(reqs,1)*100:.1f}%",
    }


@app.get("/health")
async def health():
    return {"status": "ok", "model_loaded": model is not None}


@app.get("/")
async def root():
    return {
        "name": "Тувинско-русский переводчик",
        "author": "Ali Kuzhuget (tyvan.ru)",
        "endpoints": ["POST /translate", "POST /vote", "GET /top", "GET /export/training-data", "GET /stats"],
    }

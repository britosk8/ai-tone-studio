"""Persistência local dos resultados da V1, sem armazenar os arquivos de áudio."""
from contextlib import contextmanager
import json
import os
import sqlite3
from pathlib import Path


@contextmanager
def _connect():
    path = Path(os.environ.get("TONE_DATA_DIR", str(Path(__file__).resolve().parents[2] / "data")))
    path.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(path / "tone-studio.sqlite3", timeout=30)
    connection.execute("CREATE TABLE IF NOT EXISTS records (kind TEXT, id TEXT, data TEXT, PRIMARY KEY (kind, id))")
    try:
        with connection:
            yield connection
    finally:
        connection.close()


def save_record(kind: str, record_id: str, data: dict):
    with _connect() as connection:
        connection.execute("INSERT OR REPLACE INTO records VALUES (?, ?, ?)",
                           (kind, record_id, json.dumps(data, ensure_ascii=False)))


def load_record(kind: str, record_id: str):
    with _connect() as connection:
        row = connection.execute("SELECT data FROM records WHERE kind=? AND id=?", (kind, record_id)).fetchone()
    return json.loads(row[0]) if row else None

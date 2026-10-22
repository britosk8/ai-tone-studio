"""Persistência SQLite; gravações de guitarra usam arquivos no mesmo volume de dados."""
from contextlib import contextmanager
import json
import os
import sqlite3
from pathlib import Path


@contextmanager
def _connect():
    path = data_directory()
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


def list_records(kind: str, limit: int = 100):
    with _connect() as connection:
        rows = connection.execute(
            "SELECT data FROM records WHERE kind=? ORDER BY id LIMIT ?", (kind, limit)).fetchall()
    return [json.loads(row[0]) for row in rows]


def data_directory():
    return Path(os.environ.get("TONE_DATA_DIR", str(Path(__file__).resolve().parents[2] / "data")))

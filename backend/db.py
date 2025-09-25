import os
from pathlib import Path
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine
from dotenv import load_dotenv

# carrega exatamente o .env ao lado deste arquivo
env_path = Path(__file__).parent / ".env"
load_dotenv(dotenv_path=env_path, override=True)

def _get_env(name: str, default: str | None = None, required: bool = False) -> str:
    val = os.getenv(name, default)
    if required and (val is None or str(val).strip() == ""):
        raise RuntimeError(f"Variável de ambiente ausente: {name}")
    return val

MYSQL_HOST = _get_env("MYSQL_HOST", "127.0.0.1")
MYSQL_DB   = _get_env("MYSQL_DB",   required=True)
MYSQL_USER = _get_env("MYSQL_USER", required=True)
MYSQL_PASS = _get_env("MYSQL_PASS", "")

DB_URL = f"mysql+pymysql://{MYSQL_USER}:{MYSQL_PASS}@{MYSQL_HOST}/{MYSQL_DB}?charset=utf8mb4"

engine: Engine = create_engine(
    DB_URL,
    pool_pre_ping=True,
    pool_recycle=1800,
    pool_size=5,
    max_overflow=10,
    future=True,
)

def one(sql: str, **params):
    with engine.connect() as c:
        r = c.execute(text(sql), params).mappings().first()
        return dict(r) if r else None

def all_(sql: str, **params):
    with engine.connect() as c:
        rows = c.execute(text(sql), params).mappings().all()
        return [dict(x) for x in rows]

def exec_(sql: str, **params):
    with engine.begin() as c:  # transaction
        res = c.execute(text(sql), params)
        try:
            return res.lastrowid
        except Exception:
            return res.rowcount

from __future__ import annotations
import pandas as pd
import psycopg
from .config import settings

def fetch_df(sql: str, params: tuple = ()) -> pd.DataFrame:
    if not settings.database_url:
        raise RuntimeError("DATABASE_URL is not set")
    with psycopg.connect(settings.database_url) as conn:
        return pd.read_sql_query(sql, conn, params=params)

def execute(sql: str, params: tuple = ()) -> None:
    if not settings.database_url:
        raise RuntimeError("DATABASE_URL is not set")
    with psycopg.connect(settings.database_url) as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params)
        conn.commit()

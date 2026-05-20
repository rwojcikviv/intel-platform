"""Database connection helpers for MariaDB on Zenbox.

Zenbox MariaDB ma agresywny idle timeout (~30s), więc pool_pre_ping=True
i pool_recycle są niezbędne — bez nich pierwsze zapytanie po przerwie
rzuca 'Server has gone away'.
"""
from __future__ import annotations

import os
from contextlib import contextmanager
from typing import Iterator

from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker

load_dotenv()

_engine: Engine | None = None
_SessionLocal: sessionmaker | None = None


def get_engine() -> Engine:
    """Returns shared SQLAlchemy Engine. Lazy-initialized."""
    global _engine
    if _engine is not None:
        return _engine

    host = os.getenv("DB_HOST")
    port = os.getenv("DB_PORT", "3306")
    user = os.getenv("DB_USER")
    password = os.getenv("DB_PASSWORD")
    name = os.getenv("DB_NAME")

    if not all([host, user, password, name]):
        raise RuntimeError(
            "Brak konfiguracji bazy. Sprawdź .env: DB_HOST, DB_USER, DB_PASSWORD, DB_NAME"
        )

    connect_args: dict = {}
    if os.getenv("DB_SSL_DISABLED", "0") == "1":
        connect_args["ssl"] = {"ssl_disabled": True}

    _engine = create_engine(
        f"mysql+pymysql://{user}:{password}@{host}:{port}/{name}?charset=utf8mb4",
        pool_pre_ping=True,
        pool_recycle=1800,      # recykluj połączenia po 30 min (Zenbox idle timeout)
        echo=os.getenv("DB_ECHO", "0") == "1",
        connect_args=connect_args,
    )
    return _engine


@contextmanager
def session_scope() -> Iterator[Session]:
    """Context manager dla SQLAlchemy Session z auto commit/rollback."""
    global _SessionLocal
    if _SessionLocal is None:
        _SessionLocal = sessionmaker(bind=get_engine())

    session = _SessionLocal()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()
        
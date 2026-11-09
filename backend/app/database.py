from collections.abc import Generator

from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker

from app.config import settings

engine = create_engine(settings.database_url, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def init_db() -> None:
    from app import models

    with engine.begin() as connection:
        legacy = connection.execute(text("SELECT to_regclass('public.reservations')")).scalar()
        if legacy:
            connection.execute(
                text(
                    "DROP TABLE IF EXISTS reservations, court_sessions, courts, facilities, users CASCADE"
                )
            )
    models.Base.metadata.create_all(bind=engine)

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import func, select, text

from app.database import SessionLocal
from app.models import Court, CourtSession, Facility, SessionPlayer, User

EASTERN = ZoneInfo("America/Indiana/Indianapolis")


# Builds a West Lafayette time for a sample session.
def at(year: int, month: int, day: int, hour: int, minute: int = 0) -> datetime:
    return datetime(year, month, day, hour, minute, tzinfo=EASTERN)


# Returns a start time that many minutes ago, but not before today.
def minutes_ago(minutes: int) -> datetime:
    now = datetime.now(EASTERN)
    started = now - timedelta(minutes=minutes)
    start_of_today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    if started < start_of_today:
        return start_of_today + timedelta(minutes=1)
    return started


# Inserts sample students, courts, and sessions when the database is empty.
def seed_if_empty() -> None:
    db = SessionLocal()
    try:
        existing = db.scalar(select(func.count()).select_from(Facility))
        if existing:
            return

        diana = User(name="Diana Rogers", email="drogers@purdue.edu")
        alex = User(name="Alex Kim", email="akim@purdue.edu")
        sarah = User(name="Sarah Patel", email="spatel@purdue.edu")
        db.add_all([diana, alex, sarah])

        corec = Facility(
            name="CoRec",
            address="355 N Martin Jischke Dr, West Lafayette, IN",
        )
        outdoor = Facility(
            name="Northwest Outdoor Courts",
            address="1201 Northwestern Ave, West Lafayette, IN",
        )
        db.add_all([corec, outdoor])
        db.flush()

        courts = {
            "c1": Court(facility_id=corec.id, court_number="1"),
            "c2": Court(facility_id=corec.id, court_number="2"),
            "c3": Court(facility_id=corec.id, court_number="3"),
            "c4": Court(facility_id=corec.id, court_number="4"),
            "a": Court(facility_id=outdoor.id, court_number="A"),
            "b": Court(facility_id=outdoor.id, court_number="B"),
        }
        db.add_all(courts.values())
        db.flush()

        db.add_all(
            [
                CourtSession(
                    user_id=diana.id,
                    court_id=courts["c1"].id,
                    started_at=at(2026, 11, 3, 18),
                    ended_at=at(2026, 11, 3, 19),
                ),
                CourtSession(
                    user_id=alex.id,
                    court_id=courts["c2"].id,
                    started_at=at(2026, 11, 3, 18),
                    ended_at=at(2026, 11, 3, 19),
                ),
                CourtSession(
                    user_id=sarah.id,
                    court_id=courts["c1"].id,
                    started_at=at(2026, 11, 5, 17),
                    ended_at=at(2026, 11, 5, 18, 30),
                ),
                CourtSession(
                    user_id=diana.id,
                    court_id=courts["c3"].id,
                    started_at=at(2026, 11, 7, 19),
                    ended_at=at(2026, 11, 7, 20),
                ),
                CourtSession(
                    user_id=sarah.id,
                    court_id=courts["c4"].id,
                    started_at=at(2026, 11, 8, 18),
                    ended_at=at(2026, 11, 8, 19),
                ),
                CourtSession(
                    user_id=alex.id,
                    court_id=courts["b"].id,
                    started_at=at(2026, 10, 20, 15),
                    ended_at=at(2026, 10, 20, 16),
                ),
                CourtSession(
                    user_id=diana.id,
                    court_id=courts["c1"].id,
                    started_at=minutes_ago(25),
                ),
                CourtSession(
                    user_id=sarah.id,
                    court_id=courts["c3"].id,
                    started_at=minutes_ago(50),
                ),
                CourtSession(
                    user_id=alex.id,
                    court_id=courts["a"].id,
                    started_at=minutes_ago(10),
                ),
            ]
        )
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()

# Counts the student who checked in as a player, including older rows.
def backfill_players() -> None:
    db = SessionLocal()
    try:
        missing = db.execute(
            text(
                """
                SELECT s.id, s.user_id
                FROM court_sessions s
                WHERE NOT EXISTS (
                    SELECT 1 FROM session_players sp
                    WHERE sp.session_id = s.id AND sp.user_id = s.user_id
                )
                """
            )
        ).all()
        for session_id, user_id in missing:
            db.add(SessionPlayer(session_id=session_id, user_id=user_id))
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()

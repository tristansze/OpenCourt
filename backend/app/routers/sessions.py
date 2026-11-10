from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Header, HTTPException
from sqlalchemy import select, text
from sqlalchemy.orm import Session, selectinload

from app.database import get_db
from app.models import Court, CourtSession, SessionPlayer, User
from app.schemas import SessionRead, SessionStart

router = APIRouter(prefix="/sessions", tags=["sessions"])


def to_read(session: CourtSession) -> SessionRead:
    return SessionRead(
        id=session.id,
        user_id=session.user_id,
        user_name=session.user.name,
        court_id=session.court_id,
        court_number=session.court.court_number,
        facility_id=session.court.facility_id,
        facility_name=session.court.facility.name,
        started_at=session.started_at,
        ended_at=session.ended_at,
    )


def load_session(db: Session, session_id: int) -> CourtSession:
    stmt = (
        select(CourtSession)
        .where(CourtSession.id == session_id)
        .options(
            selectinload(CourtSession.user),
            selectinload(CourtSession.court).selectinload(Court.facility),
        )
    )
    session = db.scalar(stmt)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")

    return session


def signed_in_user(db: Session, user_id: int) -> User:
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="Sign in before changing a session.")
        
    return user


def owned_session(db: Session, session_id: int, user_id: int) -> CourtSession:
    signed_in_user(db, user_id)
    session = db.get(CourtSession, session_id)

    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")

    if session.user_id != user_id:
        raise HTTPException(
            status_code=403,
            detail="Only the student who checked in can change this session.",
        )
    return session


def ensure_court_is_free(db: Session, court_id: int) -> None:
    # Lock the court row so a second check-in waits, then sees this one.
    db.execute(text("SET TRANSACTION ISOLATION LEVEL READ COMMITTED"))
    court = db.scalar(select(Court).where(Court.id == court_id).with_for_update())

    if court is None:
        raise HTTPException(status_code=400, detail="Court not found")

    active = select(CourtSession.id).where(
        CourtSession.court_id == court_id,
        CourtSession.ended_at.is_(None),
    )

    if db.scalar(active) is not None:
        raise HTTPException(status_code=409, detail="That court is already in use.")


def add_players(db: Session, session_id: int, owner_id: int, player_ids: list[int]) -> None:
    seen: set[int] = set()
    for player_id in [owner_id, *player_ids]:
        if player_id in seen:
            continue

        seen.add(player_id)

        if db.get(User, player_id) is None:
            raise HTTPException(status_code=400, detail="Student not found")

        db.add(SessionPlayer(session_id=session_id, user_id=player_id))


@router.post("", response_model=SessionRead, status_code=201)
def start_session(
    data: SessionStart,
    x_user_id: int = Header(..., alias="X-User-Id"),
    db: Session = Depends(get_db),
) -> SessionRead:
    user = signed_in_user(db, x_user_id)
    ensure_court_is_free(db, data.court_id)

    session = CourtSession(
        user_id=user.id,
        court_id=data.court_id,
        started_at=datetime.now(timezone.utc),
    )

    db.add(session)
    db.flush()

    add_players(db, session.id, user.id, data.player_ids)
    db.flush()

    return to_read(load_session(db, session.id))


@router.post("/{session_id}/end", response_model=SessionRead)
def end_session(
    session_id: int,
    x_user_id: int = Header(..., alias="X-User-Id"),
    db: Session = Depends(get_db),
) -> SessionRead:
    session = owned_session(db, session_id, x_user_id)
    if session.ended_at is not None:
        raise HTTPException(status_code=400, detail="That session already ended.")
    session.ended_at = datetime.now(timezone.utc)
    db.flush()
    return to_read(load_session(db, session.id))


@router.delete("/{session_id}", status_code=204)
def delete_session(
    session_id: int,
    x_user_id: int = Header(..., alias="X-User-Id"),
    db: Session = Depends(get_db),
) -> None:
    session = owned_session(db, session_id, x_user_id)
    db.delete(session)

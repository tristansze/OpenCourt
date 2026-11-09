from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, text
from sqlalchemy.orm import Session, selectinload

from app.database import get_db
from app.models import Court, CourtSession, User
from app.schemas import SessionRead, SessionStart, SessionUpdate

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
        court_type=session.court.court_type,
        started_at=session.started_at,
        ended_at=session.ended_at,
    )


def load_session(db: Session, session_id: int) -> CourtSession | None:
    stmt = (
        select(CourtSession)
        .where(CourtSession.id == session_id)
        .options(
            selectinload(CourtSession.user),
            selectinload(CourtSession.court).selectinload(Court.facility),
        )
    )
    return db.scalar(stmt)


def ensure_court_is_free(db: Session, court_id: int, exclude_id: int | None) -> None:
    # READ COMMITTED plus a lock on the court row: a second check-in for this
    # court waits until this transaction commits, then sees the open session.
    db.execute(text("SET TRANSACTION ISOLATION LEVEL READ COMMITTED"))
    court = db.scalar(select(Court).where(Court.id == court_id).with_for_update())
    if court is None:
        raise HTTPException(status_code=400, detail="Court not found")

    active = select(CourtSession.id).where(
        CourtSession.court_id == court_id,
        CourtSession.ended_at.is_(None),
    )
    if exclude_id is not None:
        active = active.where(CourtSession.id != exclude_id)
    if db.scalar(active) is not None:
        raise HTTPException(status_code=409, detail="That court is already in use.")


@router.get("", response_model=list[SessionRead])
def list_sessions(db: Session = Depends(get_db)) -> list[SessionRead]:
    stmt = (
        select(CourtSession)
        .options(
            selectinload(CourtSession.user),
            selectinload(CourtSession.court).selectinload(Court.facility),
        )
        .order_by(CourtSession.ended_at.is_(None).desc(), CourtSession.started_at.desc())
    )
    return [to_read(session) for session in db.scalars(stmt)]


@router.post("", response_model=SessionRead, status_code=201)
def start_session(data: SessionStart, db: Session = Depends(get_db)) -> SessionRead:
    if db.get(User, data.user_id) is None:
        raise HTTPException(status_code=400, detail="Student not found")
    ensure_court_is_free(db, data.court_id, exclude_id=None)
    session = CourtSession(
        user_id=data.user_id,
        court_id=data.court_id,
        started_at=datetime.now(timezone.utc),
    )
    db.add(session)
    db.flush()
    created = load_session(db, session.id)
    if created is None:
        raise HTTPException(status_code=500, detail="Could not start session")
    return to_read(created)


@router.put("/{session_id}", response_model=SessionRead)
def update_session(
    session_id: int,
    data: SessionUpdate,
    db: Session = Depends(get_db),
) -> SessionRead:
    session = db.get(CourtSession, session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")
    if db.get(User, data.user_id) is None:
        raise HTTPException(status_code=400, detail="Student not found")
    if data.ended_at is None:
        ensure_court_is_free(db, data.court_id, exclude_id=session_id)
    else:
        court = db.get(Court, data.court_id)
        if court is None:
            raise HTTPException(status_code=400, detail="Court not found")

    session.user_id = data.user_id
    session.court_id = data.court_id
    session.started_at = data.started_at
    session.ended_at = data.ended_at
    db.flush()
    updated = load_session(db, session_id)
    if updated is None:
        raise HTTPException(status_code=500, detail="Could not update session")
    return to_read(updated)


@router.post("/{session_id}/end", response_model=SessionRead)
def end_session(session_id: int, db: Session = Depends(get_db)) -> SessionRead:
    session = db.get(CourtSession, session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")
    if session.ended_at is not None:
        raise HTTPException(status_code=400, detail="That session already ended.")
    session.ended_at = datetime.now(timezone.utc)
    db.flush()
    ended = load_session(db, session_id)
    if ended is None:
        raise HTTPException(status_code=500, detail="Could not end session")
    return to_read(ended)


@router.delete("/{session_id}", status_code=204)
def delete_session(session_id: int, db: Session = Depends(get_db)) -> None:
    session = db.get(CourtSession, session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")
    db.delete(session)

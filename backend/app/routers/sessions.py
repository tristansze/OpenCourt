from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Header, HTTPException
from sqlalchemy import select, text
from sqlalchemy.orm import Session, selectinload

from app.database import get_db
from app.models import Court, CourtSession, SessionPlayer, User
from app.schemas import SessionRead, SessionStart, TagPlayer

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


def signed_in_user(db: Session, user_id: int) -> User:
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="Sign in before changing a session.")
    return user


def require_owner(session: CourtSession, user_id: int) -> None:
    if session.user_id != user_id:
        raise HTTPException(
            status_code=403,
            detail="Only the student who checked in can change this session.",
        )


@router.post("", response_model=SessionRead, status_code=201)
def start_session(
    data: SessionStart,
    x_user_id: int = Header(..., alias="X-User-Id"),
    db: Session = Depends(get_db),
) -> SessionRead:
    user = signed_in_user(db, x_user_id)
    ensure_court_is_free(db, data.court_id, exclude_id=None)
    session = CourtSession(
        user_id=user.id,
        court_id=data.court_id,
        started_at=datetime.now(timezone.utc),
    )
    db.add(session)
    db.flush()
    tagged = {user.id}
    db.add(SessionPlayer(session_id=session.id, user_id=user.id))
    for player_id in data.player_ids:
        if player_id in tagged:
            continue
        if db.get(User, player_id) is None:
            raise HTTPException(status_code=400, detail="Student not found")
        db.add(SessionPlayer(session_id=session.id, user_id=player_id))
        tagged.add(player_id)
    db.flush()
    created = load_session(db, session.id)
    if created is None:
        raise HTTPException(status_code=500, detail="Could not start session")
    return to_read(created)


@router.post("/{session_id}/end", response_model=SessionRead)
def end_session(
    session_id: int,
    x_user_id: int = Header(..., alias="X-User-Id"),
    db: Session = Depends(get_db),
) -> SessionRead:
    signed_in_user(db, x_user_id)
    session = db.get(CourtSession, session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")
    require_owner(session, x_user_id)
    if session.ended_at is not None:
        raise HTTPException(status_code=400, detail="That session already ended.")
    session.ended_at = datetime.now(timezone.utc)
    db.flush()
    ended = load_session(db, session_id)
    if ended is None:
        raise HTTPException(status_code=500, detail="Could not end session")
    return to_read(ended)


@router.delete("/{session_id}", status_code=204)
def delete_session(
    session_id: int,
    x_user_id: int = Header(..., alias="X-User-Id"),
    db: Session = Depends(get_db),
) -> None:
    signed_in_user(db, x_user_id)
    session = db.get(CourtSession, session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")
    require_owner(session, x_user_id)
    db.delete(session)


@router.post("/{session_id}/players", response_model=SessionRead)
def tag_player(
    session_id: int,
    data: TagPlayer,
    x_user_id: int = Header(..., alias="X-User-Id"),
    db: Session = Depends(get_db),
) -> SessionRead:
    signed_in_user(db, x_user_id)
    session = db.get(CourtSession, session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")
    require_owner(session, x_user_id)
    if session.ended_at is not None:
        raise HTTPException(status_code=400, detail="That session already ended.")
    if db.get(User, data.user_id) is None:
        raise HTTPException(status_code=400, detail="Student not found")
    already = db.scalar(
        select(SessionPlayer.id).where(
            SessionPlayer.session_id == session_id,
            SessionPlayer.user_id == data.user_id,
        )
    )
    if already is not None:
        raise HTTPException(status_code=409, detail="That student is already in this game.")
    db.add(SessionPlayer(session_id=session_id, user_id=data.user_id))
    db.flush()
    updated = load_session(db, session_id)
    if updated is None:
        raise HTTPException(status_code=500, detail="Could not tag that student")
    return to_read(updated)

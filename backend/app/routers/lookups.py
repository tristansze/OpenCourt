from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Court, Facility, User
from app.schemas import CourtRead, FacilityRead, UserCreate, UserRead

router = APIRouter(tags=["lookups"])


# Returns every student for the sign-in list.
@router.get("/users", response_model=list[UserRead])
def list_users(db: Session = Depends(get_db)) -> list[User]:
    return list(db.scalars(select(User).order_by(User.name)))


# Adds a student with a Purdue email.
@router.post("/users", response_model=UserRead, status_code=201)
def create_user(data: UserCreate, db: Session = Depends(get_db)) -> User:
    name = data.name.strip()
    email = data.email.strip().lower()
    if not name:
        raise HTTPException(status_code=400, detail="Enter your name.")
    if not email.endswith("@purdue.edu"):
        raise HTTPException(status_code=400, detail="Use a Purdue email.")
    user = User(name=name, email=email)
    db.add(user)
    try:
        db.flush()
    except IntegrityError:
        raise HTTPException(status_code=409, detail="That email is already registered.") from None
    return user


# Returns every facility for the report picker.
@router.get("/facilities", response_model=list[FacilityRead])
def list_facilities(db: Session = Depends(get_db)) -> list[Facility]:
    return list(db.scalars(select(Facility).order_by(Facility.name)))


# Returns courts for the report picker, optionally for one facility.
@router.get("/courts", response_model=list[CourtRead])
def list_courts(
    facility_id: int | None = None,
    db: Session = Depends(get_db),
) -> list[CourtRead]:

    stmt = (
        select(Court, Facility.name)
        .join(Facility, Facility.id == Court.facility_id)
        .order_by(Facility.name, Court.court_number)
    )
    if facility_id is not None:
        stmt = stmt.where(Court.facility_id == facility_id)

    return [
        CourtRead(
            id=court.id,
            facility_id=court.facility_id,
            facility_name=facility_name,
            court_number=court.court_number,
        )
        for court, facility_name in db.execute(stmt)
    ]

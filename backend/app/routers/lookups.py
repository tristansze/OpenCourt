from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Court, Facility, User
from app.schemas import CourtRead, FacilityRead, UserRead

router = APIRouter(tags=["lookups"])


@router.get("/users", response_model=list[UserRead])
def list_users(db: Session = Depends(get_db)) -> list[User]:
    return list(db.scalars(select(User).order_by(User.name)))


@router.get("/facilities", response_model=list[FacilityRead])
def list_facilities(db: Session = Depends(get_db)) -> list[Facility]:
    return list(db.scalars(select(Facility).order_by(Facility.name)))


@router.get("/courts", response_model=list[CourtRead])
def list_courts(
    facility_id: int | None = None,
    db: Session = Depends(get_db),
) -> list[CourtRead]:
    # Dropdown of courts. facility_id is optional so the report can show every court.
    # uq_courts_facility_number starts with facility_id, so this filter uses that index.
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
            court_type=court.court_type,
        )
        for court, facility_name in db.execute(stmt)
    ]


@router.get("/court-types", response_model=list[str])
def list_court_types(db: Session = Depends(get_db)) -> list[str]:
    rows = db.scalars(select(Court.court_type).distinct().order_by(Court.court_type))
    return list(rows)

from itertools import groupby

from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas import Occupancy, OccupancyCourt, OccupancyFacility

router = APIRouter(tags=["occupancy"])

# A court is in use when a check-in has not ended.
COURTS_IN_USE_SQL = "SELECT COUNT(*) FROM court_sessions WHERE ended_at IS NULL"

COURT_STATUS_SQL = """
SELECT
    f.id AS facility_id,
    f.name AS facility_name,
    f.address,
    c.id AS court_id,
    c.court_number,
    s.id AS session_id,
    s.user_id AS player_user_id,
    u.name AS player_name,
    s.started_at
FROM courts c
JOIN facilities f ON f.id = c.facility_id
LEFT JOIN court_sessions s ON s.court_id = c.id AND s.ended_at IS NULL
LEFT JOIN users u ON u.id = s.user_id
ORDER BY f.name, c.court_number
"""


def percent(in_use: int, total: int) -> int:
    if total == 0:
        return 0
    return round(100 * in_use / total)


def court_from_row(row) -> OccupancyCourt:
    return OccupancyCourt(
        id=row["court_id"],
        court_number=row["court_number"],
        in_use=row["session_id"] is not None,
        session_id=row["session_id"],
        player_user_id=row["player_user_id"],
        player_name=row["player_name"],
        started_at=row["started_at"],
    )


@router.get("/occupancy", response_model=Occupancy)
def get_occupancy(db: Session = Depends(get_db)) -> Occupancy:
    db.execute(text("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ"))
    courts_in_use = int(db.execute(text(COURTS_IN_USE_SQL)).scalar_one())
    rows = db.execute(text(COURT_STATUS_SQL)).mappings().all()

    facilities: list[OccupancyFacility] = []
    for _, group in groupby(rows, key=lambda row: row["facility_id"]):
        grouped = list(group)
        first = grouped[0]
        courts = [court_from_row(row) for row in grouped]
        in_use = sum(court.in_use for court in courts)
        facilities.append(
            OccupancyFacility(
                id=first["facility_id"],
                name=first["facility_name"],
                address=first["address"],
                courts_in_use=in_use,
                court_count=len(courts),
                in_use_percent=percent(in_use, len(courts)),
                courts=courts,
            )
        )

    court_count = sum(facility.court_count for facility in facilities)
    return Occupancy(
        courts_in_use=courts_in_use,
        court_count=court_count,
        in_use_percent=percent(courts_in_use, court_count),
        facilities=facilities,
    )

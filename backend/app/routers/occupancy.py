from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas import Occupancy, OccupancyCourt, OccupancyFacility

router = APIRouter(tags=["occupancy"])

# A court is in use when someone has checked in and has not checked out.
# Anyone can call this. It does not require a signed-in player.
COURTS_IN_USE_SQL = "SELECT COUNT(*) FROM court_sessions WHERE ended_at IS NULL"

COURT_STATUS_SQL = """
SELECT
    f.id AS facility_id,
    f.name AS facility_name,
    f.address,
    c.id AS court_id,
    c.court_number,
    c.court_type,
    s.id AS session_id,
    s.user_id AS player_user_id,
    u.name AS player_name,
    (
        SELECT string_agg(u2.name, ', ' ORDER BY (u2.id = s.user_id) DESC, u2.name)
        FROM session_players sp
        JOIN users u2 ON u2.id = sp.user_id
        WHERE sp.session_id = s.id
    ) AS player_names,
    (
        SELECT COALESCE(array_agg(sp.user_id), ARRAY[]::integer[])
        FROM session_players sp
        WHERE sp.session_id = s.id
    ) AS player_user_ids,
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


@router.get("/occupancy", response_model=Occupancy)
def get_occupancy(db: Session = Depends(get_db)) -> Occupancy:
    db.execute(text("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ"))
    courts_in_use = int(db.execute(text(COURTS_IN_USE_SQL)).scalar_one())
    rows = db.execute(text(COURT_STATUS_SQL)).mappings().all()

    facilities: list[OccupancyFacility] = []
    by_id: dict[int, OccupancyFacility] = {}
    for row in rows:
        facility = by_id.get(row["facility_id"])
        if facility is None:
            facility = OccupancyFacility(
                id=row["facility_id"],
                name=row["facility_name"],
                address=row["address"],
                courts_in_use=0,
                court_count=0,
                in_use_percent=0,
                courts=[],
            )
            by_id[row["facility_id"]] = facility
            facilities.append(facility)

        in_use = row["session_id"] is not None
        facility.courts.append(
            OccupancyCourt(
                id=row["court_id"],
                court_number=row["court_number"],
                court_type=row["court_type"],
                in_use=in_use,
                session_id=row["session_id"],
                player_user_id=row["player_user_id"],
                player_name=row["player_name"],
                player_names=row["player_names"],
                player_user_ids=list(row["player_user_ids"] or []),
                started_at=row["started_at"],
            )
        )
        facility.court_count += 1
        if in_use:
            facility.courts_in_use += 1

    for facility in facilities:
        facility.in_use_percent = percent(facility.courts_in_use, facility.court_count)

    court_count = sum(facility.court_count for facility in facilities)
    return Occupancy(
        courts_in_use=courts_in_use,
        court_count=court_count,
        in_use_percent=percent(courts_in_use, court_count),
        facilities=facilities,
    )

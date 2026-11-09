from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas import CourtUsageReport, CourtUsageRow, SessionRead

router = APIRouter(prefix="/reports", tags=["reports"])

# Values are always bound parameters. Filter text is chosen in code, never taken
# from the client, so a user cannot inject SQL through a facility or court id.
STATS_SQL = """
SELECT
    COUNT(*) AS total_sessions,
    COUNT(s.ended_at) AS finished_sessions,
    COUNT(DISTINCT s.user_id) AS unique_users,
    AVG(EXTRACT(EPOCH FROM (s.ended_at - s.started_at)) / 60.0) AS average_duration_minutes
FROM court_sessions s
JOIN courts c ON c.id = s.court_id
JOIN facilities f ON f.id = c.facility_id
WHERE {filters}
"""

BY_COURT_SQL = """
SELECT
    c.id AS court_id,
    f.name AS facility_name,
    c.court_number,
    c.court_type,
    COUNT(*) AS session_count
FROM court_sessions s
JOIN courts c ON c.id = s.court_id
JOIN facilities f ON f.id = c.facility_id
WHERE {filters}
GROUP BY c.id, f.name, c.court_number, c.court_type
ORDER BY session_count DESC, f.name, c.court_number
"""

ROWS_SQL = """
SELECT
    s.id,
    s.user_id,
    u.name AS user_name,
    s.court_id,
    c.court_number,
    c.facility_id,
    f.name AS facility_name,
    c.court_type,
    s.started_at,
    s.ended_at
FROM court_sessions s
JOIN users u ON u.id = s.user_id
JOIN courts c ON c.id = s.court_id
JOIN facilities f ON f.id = c.facility_id
WHERE {filters}
ORDER BY s.started_at
"""


def report_filters(
    facility_id: int | None,
    court_id: int | None,
    court_type: str | None,
) -> tuple[str, dict]:
    clauses = [
        "s.started_at >= :start_time",
        "s.started_at < :end_time",
    ]
    params: dict = {}
    if facility_id is not None:
        clauses.append("c.facility_id = :facility_id")
        params["facility_id"] = facility_id
    if court_id is not None:
        clauses.append("s.court_id = :court_id")
        params["court_id"] = court_id
    if court_type:
        clauses.append("c.court_type = :court_type")
        params["court_type"] = court_type
    return " AND ".join(clauses), params


@router.get("/court-usage", response_model=CourtUsageReport)
def court_usage_report(
    start: datetime = Query(..., description="Inclusive start of the range"),
    end: datetime = Query(..., description="Exclusive end of the range"),
    facility_id: int | None = None,
    court_id: int | None = None,
    court_type: str | None = None,
    db: Session = Depends(get_db),
) -> CourtUsageReport:
    if end <= start:
        raise HTTPException(status_code=400, detail="end must be after start")

    # One snapshot for the stats query, the GROUP BY query, and the row list.
    db.execute(text("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ"))

    filters, params = report_filters(facility_id, court_id, court_type)
    params["start_time"] = start
    params["end_time"] = end

    stats = db.execute(text(STATS_SQL.format(filters=filters)), params).one()
    by_court = db.execute(text(BY_COURT_SQL.format(filters=filters)), params).mappings()
    rows = db.execute(text(ROWS_SQL.format(filters=filters)), params).mappings()

    average = stats.average_duration_minutes
    return CourtUsageReport(
        total_sessions=int(stats.total_sessions or 0),
        finished_sessions=int(stats.finished_sessions or 0),
        unique_users=int(stats.unique_users or 0),
        average_duration_minutes=float(average) if average is not None else None,
        by_court=[CourtUsageRow.model_validate(dict(row)) for row in by_court],
        sessions=[SessionRead.model_validate(dict(row)) for row in rows],
    )

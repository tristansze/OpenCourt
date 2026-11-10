from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas import CourtUsageReport, CourtUsageRow

router = APIRouter(prefix="/reports", tags=["reports"])

# Find by date and facility
FILTERED_SESSIONS = """
FROM court_sessions s
JOIN courts c ON c.id = s.court_id
JOIN facilities f ON f.id = c.facility_id
WHERE s.started_at >= :start_time
  AND s.started_at < :end_time
  AND (CAST(:facility_id AS INTEGER) IS NULL OR c.facility_id = :facility_id)
  AND (CAST(:court_id AS INTEGER) IS NULL OR s.court_id = :court_id)
"""

# Count sessions, users, and avg
STATS_SQL = f"""
SELECT
    COUNT(*) AS total_sessions,
    COUNT(DISTINCT s.user_id) AS unique_users,
    AVG(EXTRACT(EPOCH FROM (s.ended_at - s.started_at)) / 60.0) AS average_duration_minutes
{FILTERED_SESSIONS}
"""

# Group by clause
BY_COURT_SQL = f"""
SELECT
    c.id AS court_id,
    f.name AS facility_name,
    c.court_number,
    COUNT(*) AS session_count
{FILTERED_SESSIONS}
GROUP BY c.id, f.name, c.court_number
ORDER BY session_count DESC, f.name, c.court_number
"""

# Returns session totals and per-court counts for the chosen filters.
@router.get("/court-usage", response_model=CourtUsageReport)
def court_usage_report(
    start: datetime = Query(..., description="Inclusive start of the range"),
    end: datetime = Query(..., description="Exclusive end of the range"),
    facility_id: int | None = None,
    court_id: int | None = None,
    db: Session = Depends(get_db),
) -> CourtUsageReport:

    if end <= start:
        raise HTTPException(status_code=400, detail="end must be after start")

    db.execute(text("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ"))
    params = {
        "start_time": start,
        "end_time": end,
        "facility_id": facility_id,
        "court_id": court_id,
    }
    stats = db.execute(text(STATS_SQL), params).one()
    by_court = db.execute(text(BY_COURT_SQL), params).mappings()

    average = stats.average_duration_minutes
    return CourtUsageReport(
        total_sessions=int(stats.total_sessions or 0),
        unique_users=int(stats.unique_users or 0),
        average_duration_minutes=float(average) if average is not None else None,
        by_court=[CourtUsageRow.model_validate(dict(row)) for row in by_court],
    )

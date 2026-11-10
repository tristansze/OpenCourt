from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas import LeaderboardEntry

router = APIRouter(tags=["leaderboard"])

# Each tagged student, and the student who checked in, counts as one game.
LEADERBOARD_SQL = """
SELECT
    u.id AS user_id,
    u.name,
    COUNT(sp.session_id) AS games
FROM users u
LEFT JOIN session_players sp ON sp.user_id = u.id
GROUP BY u.id, u.name
ORDER BY games DESC, u.name
"""


# Ranks students by how many games they have played.
@router.get("/leaderboard", response_model=list[LeaderboardEntry])
def leaderboard(db: Session = Depends(get_db)) -> list[LeaderboardEntry]:
    rows = db.execute(text(LEADERBOARD_SQL)).mappings().all()
    return [
        LeaderboardEntry(
            rank=index,
            user_id=row["user_id"],
            name=row["name"],
            games=int(row["games"]),
        )
        for index, row in enumerate(rows, start=1)
    ]

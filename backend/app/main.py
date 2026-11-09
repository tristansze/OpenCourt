from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.database import init_db
from app.routers import leaderboard, lookups, occupancy, reports, sessions
from app.seed import backfill_players, seed_if_empty


@asynccontextmanager
async def lifespan(_: FastAPI):
    init_db()
    seed_if_empty()
    backfill_players()
    yield


app = FastAPI(title="Purdue OpenCourt API", version="0.2.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(lookups.router)
app.include_router(occupancy.router)
app.include_router(sessions.router)
app.include_router(reports.router)
app.include_router(leaderboard.router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}

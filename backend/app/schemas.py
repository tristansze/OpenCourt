from datetime import datetime

from pydantic import BaseModel, ConfigDict


class UserRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    email: str


class UserCreate(BaseModel):
    name: str
    email: str


class FacilityRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    address: str


class CourtRead(BaseModel):
    id: int
    facility_id: int
    facility_name: str
    court_number: str


class SessionRead(BaseModel):
    id: int
    user_id: int
    user_name: str
    court_id: int
    court_number: str
    facility_id: int
    facility_name: str
    started_at: datetime
    ended_at: datetime | None


class SessionStart(BaseModel):
    court_id: int
    player_ids: list[int] = []


class OccupancyCourt(BaseModel):
    id: int
    court_number: str
    in_use: bool
    session_id: int | None = None
    player_user_id: int | None = None
    player_name: str | None = None
    started_at: datetime | None = None


class OccupancyFacility(BaseModel):
    id: int
    name: str
    address: str
    courts_in_use: int
    court_count: int
    in_use_percent: int
    courts: list[OccupancyCourt]


class Occupancy(BaseModel):
    courts_in_use: int
    court_count: int
    in_use_percent: int
    facilities: list[OccupancyFacility]


class CourtUsageRow(BaseModel):
    court_id: int
    facility_name: str
    court_number: str
    session_count: int


class LeaderboardEntry(BaseModel):
    rank: int
    user_id: int
    name: str
    games: int


class CourtUsageReport(BaseModel):
    total_sessions: int
    unique_users: int
    average_duration_minutes: float | None
    by_court: list[CourtUsageRow]

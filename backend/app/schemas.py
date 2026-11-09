from datetime import datetime

from pydantic import BaseModel, ConfigDict, model_validator


class UserRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
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
    court_type: str


class SessionRead(BaseModel):
    id: int
    user_id: int
    user_name: str
    court_id: int
    court_number: str
    facility_id: int
    facility_name: str
    court_type: str
    started_at: datetime
    ended_at: datetime | None


class SessionStart(BaseModel):
    user_id: int
    court_id: int


class SessionUpdate(BaseModel):
    user_id: int
    court_id: int
    started_at: datetime
    ended_at: datetime | None = None

    @model_validator(mode="after")
    def end_after_start(self) -> "SessionUpdate":
        if self.ended_at is not None and self.ended_at <= self.started_at:
            raise ValueError("ended_at must be after started_at")
        return self


class OccupancyCourt(BaseModel):
    id: int
    court_number: str
    court_type: str
    in_use: bool
    session_id: int | None = None
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
    court_type: str
    session_count: int


class CourtUsageReport(BaseModel):
    total_sessions: int
    finished_sessions: int
    unique_users: int
    average_duration_minutes: float | None
    by_court: list[CourtUsageRow]
    sessions: list[SessionRead]

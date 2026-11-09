-- Purdue OpenCourt database design
--
-- The API creates this schema from backend/app/models.py when it starts.
-- court_sessions is the main table: a player checks in when a group starts
-- and checks out when they leave. ended_at stays empty while they are playing.
-- users, facilities, and courts are supporting tables. The phone loads them
-- from the database to fill the pickers.

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(120) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE
);

CREATE TABLE facilities (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL UNIQUE,
    address VARCHAR(300) NOT NULL
);

CREATE TABLE courts (
    id SERIAL PRIMARY KEY,
    facility_id INTEGER NOT NULL REFERENCES facilities (id) ON DELETE RESTRICT,
    court_number VARCHAR(40) NOT NULL,
    court_type VARCHAR(20) NOT NULL,
    CONSTRAINT uq_courts_facility_number UNIQUE (facility_id, court_number),
    CONSTRAINT ck_courts_type CHECK (court_type IN ('indoor', 'outdoor'))
);

CREATE TABLE court_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    court_id INTEGER NOT NULL REFERENCES courts (id) ON DELETE RESTRICT,
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_sessions_time_order CHECK (ended_at IS NULL OR ended_at > started_at)
);

-- One open check-in per court. This is what "in use" means.
CREATE UNIQUE INDEX uq_active_session_per_court
    ON court_sessions (court_id)
    WHERE ended_at IS NULL;

-- Usage report date filter, and the session list ordered by start time.
CREATE INDEX ix_sessions_started_at ON court_sessions (started_at);

-- "Is this court in use?" and the report filtered to one court.
CREATE INDEX ix_sessions_court_started ON court_sessions (court_id, started_at);

-- The court picker filters by facility_id. uq_courts_facility_number starts
-- with facility_id, so PostgreSQL can use that index for the dropdown.

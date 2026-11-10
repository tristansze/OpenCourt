-- Database Design
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
lity_id INTEGER NOT NULL REFERENCES facilities (id) ON DELETE RESTRICT,
    court_numb
CREATE TABLE courts (
    id SERIAL PRIMARY KEY,
    facier VARCHAR(40) NOT NULL,
    CONSTRAINT uq_courts_facility_number UNIQUE (facility_id, court_number)
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

CREATE TABLE session_players (
    id SERIAL PRIMARY KEY,
    session_id INTEGER NOT NULL REFERENCES court_sessions (id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT uq_session_player UNIQUE (session_id, user_id)
);

-- One open check-in per court
CREATE UNIQUE INDEX uq_active_session_per_court
    ON court_sessions (court_id)
    WHERE ended_at IS NULL;

-- Report date filter and the session list ordered by start time.
CREATE INDEX ix_sessions_started_at ON court_sessions (started_at);

-- Checks if this court is in use
CREATE INDEX ix_sessions_court_started ON court_sessions (court_id, started_at);

-- Leaderboard for games per student
CREATE INDEX ix_session_players_user ON session_players (user_id);

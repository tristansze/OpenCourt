# Purdue OpenCourt

SwiftUI iPhone app for seeing which Purdue pickleball courts are in use. A player checks in when their group starts and checks out when they leave. Anyone can open the app and see the live occupancy and a usage report.

```
SwiftUI  ->  FastAPI  ->  PostgreSQL
```

Stage 2 uses one main table, `court_sessions`. Students, facilities, and courts are supporting tables. The phone builds its pickers from those tables. A court is in use when it has a session with an empty `ended_at`.

## Run PostgreSQL

This project expects a local database named `opencourt`.

```bash
/opt/homebrew/opt/postgresql@14/bin/pg_ctl \
  -D /opt/homebrew/var/postgresql@14 \
  -l /opt/homebrew/var/log/postgresql@14.log start

/opt/homebrew/opt/postgresql@14/bin/createdb opencourt   # only the first time
```

The connection string is `postgresql+psycopg://localhost:5432/opencourt`. Override it with `DATABASE_URL` if you use a different host, user, or password. Do not put a password in the repo.

## Run the API

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

On startup the API creates the tables from `app/models.py` and, if the database is empty, loads sample facilities, courts, students, and sessions. Open http://127.0.0.1:8000/docs to see the endpoints.

`backend/schema.sql` is the same design in SQL: primary keys, foreign keys, checks, and indexes.

## Run the iOS app

1. Open `ios/OpenCourt/OpenCourt.xcodeproj` in Xcode.
2. Choose an iPhone simulator.
3. Press Run.

The simulator uses `http://127.0.0.1:8000`, so the API has to be running first.

- **Courts** shows how many courts are in use, and only the name of the student who checked in. Anyone can look. Sign in, tap an open court, and check in. Tag friends on that screen. Only that student can end or cancel.
- **Leaders** ranks students by games played. A tag counts as a game for that student.
- **Usage** is the filtered report: total sessions, unique students, average duration, and sessions per court.

## Reset the sample data

```bash
/opt/homebrew/opt/postgresql@14/bin/dropdb opencourt
/opt/homebrew/opt/postgresql@14/bin/createdb opencourt
```

Restart the API. It recreates the tables and seed rows. Restart does not reseed while facilities already exist, so a demo delete stays deleted until you drop the database.

## Stage 2 demo

Aim for 8–12 minutes. Record on a fresh sample database. The Courts tab starts at **3 of 6 courts in use (50%)**: CoRec courts 1 and 3, and Northwest court A. CoRec court 2 is open. The November usage report starts at **8 sessions, 5 finished, 3 students, 66.0 min average**.

1. **Design (about 2 minutes).** Open `backend/schema.sql`. Point at `court_sessions` as the main table. `ended_at` is empty while a group is playing. `user_id` and `court_id` are foreign keys. `uq_active_session_per_court` is why two groups cannot check in to the same court. `ix_sessions_started_at` supports the usage report.
2. **Live occupancy (about 2 minutes).** Open the Courts tab and read **3 of 6** and **50%**. Open `backend/app/routers/occupancy.py` and show `SELECT COUNT(*) FROM court_sessions WHERE ended_at IS NULL`. Say anyone can view this. Checking in is what creates the number.
3. **Report before the change (about 1 minute).** Open Usage. Leave the dates on this month. Read **8 sessions, 3 students, 66.0 min**. The average ignores sessions that are still in progress. Open `reports.py` and point at `COUNT`, `AVG`, `JOIN`, and `GROUP BY`.
4. **Sign in, then insert (about 2 minutes).** Tap **Sign in** and choose Tristan Lee. The names come from `GET /users`. CoRec Court 1 shows **End** and **Cancel** because Tristan checked in. Switch to Alex Kim and those buttons disappear. Sign back in as Tristan, tap **Play** on open CoRec Court 2, and check in. The count becomes **4 of 6**. Show `start_session` in `sessions.py`: the user id comes from the `X-User-Id` header.
5. **Report after check-in (about 1 minute).** Generate the usage report. Sessions is now **9**. The average is still **66.0** because the new session has not ended. There is no list of individual visits on this screen.
6. **Update, then delete (about 2 minutes).** As Tristan, tap **End** on Court 2. That sets `ended_at` (the update). Occupancy returns to **3 of 6**, and the average changes. Check in on Court 2 again, then tap **Cancel**. That deletes the row. Generate the report again. It returns to **8 sessions** and **66.0 min**. In `end_session` and `delete_session`, point at the check that the signed-in student owns the row.
7. **Pickers come from the database (about 1 minute).** On Usage, change Facility to CoRec and generate. Northwest court A disappears. In `ReportView.swift`, show `ForEach(facilities)`. The names come from `list_facilities` in `lookups.py`. Set From to Oct 1 to include the extra October session.

Checking in to a court that is already in use returns 409 and the app shows “That court is already in use.”

## What is left for stage 3

Stage 3 is a shorter demo about course concepts, plus a link to the code. These are already in the code and only need to be explained on camera:

- **SQL injection.** Report queries send values as bound parameters (`:start_time`, `:court_id`). Filter column names are written in code, not copied from the request. A court type of `indoor' OR '1'='1` is treated as a literal string and matches nothing.
- **Indexes.** `ix_sessions_started_at` supports the usage report date range. `uq_active_session_per_court` supports “which courts are in use?” and blocks a second check-in. `uq_courts_facility_number` supports the court dropdown filtered by facility.
- **Transactions and isolation.** `get_db` commits on success and rolls back on error. Checking in locks the court row (`FOR UPDATE`) at `READ COMMITTED`, so two players cannot take the same court. Occupancy and the report use `REPEATABLE READ` so the count and the court list see one snapshot.
- **AI usage.** Read the section below out loud. It is required.

Not built yet: a map and login. Cloud hosting is extra credit for stage 3.

## AI Usage

- **Tool:** Cursor, using the Grok coding assistant.
- **Tasks:** Project structure, FastAPI routes, SQLAlchemy models, the occupancy and usage SQL, SwiftUI screens, and this README. The first version used reservations. It was changed to check-in sessions so the app matches walk-up play at the CoRec.
- **Verification:** The API was run against local PostgreSQL. Check-in, edit, end, delete, a second check-in on a busy court, the live occupancy count, and the November usage report were checked with HTTP requests. The SwiftUI project is built in Xcode.
- **Your responsibility:** Review the code you will talk through, especially `occupancy.py`, `sessions.py`, `reports.py`, `models.py`, and the Courts and Usage screens. Be able to explain the keys, the count query, the report query, and why user input is bound instead of concatenated.

from datetime import datetime

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    String,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    email: Mapped[str] = mapped_column(String(255), nullable=False, unique=True)

    sessions: Mapped[list["CourtSession"]] = relationship(back_populates="user")
    appearances: Mapped[list["SessionPlayer"]] = relationship(back_populates="user")


class Facility(Base):
    __tablename__ = "facilities"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False, unique=True)
    address: Mapped[str] = mapped_column(String(300), nullable=False)

    courts: Mapped[list["Court"]] = relationship(back_populates="facility")


class Court(Base):
    __tablename__ = "courts"
    __table_args__ = (
        UniqueConstraint("facility_id", "court_number", name="uq_courts_facility_number"),
        CheckConstraint(
            "court_type IN ('indoor', 'outdoor')",
            name="ck_courts_type",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    facility_id: Mapped[int] = mapped_column(
        ForeignKey("facilities.id", ondelete="RESTRICT"), nullable=False
    )
    court_number: Mapped[str] = mapped_column(String(40), nullable=False)
    court_type: Mapped[str] = mapped_column(String(20), nullable=False)

    facility: Mapped[Facility] = relationship(back_populates="courts")
    sessions: Mapped[list["CourtSession"]] = relationship(back_populates="court")


class CourtSession(Base):
    """One check-in. ended_at is empty while that group is still playing."""

    __tablename__ = "court_sessions"
    __table_args__ = (
        CheckConstraint(
            "ended_at IS NULL OR ended_at > started_at",
            name="ck_sessions_time_order",
        ),
        # At most one group on a court at a time.
        Index(
            "uq_active_session_per_court",
            "court_id",
            unique=True,
            postgresql_where=text("ended_at IS NULL"),
        ),
        # Usage report date range, and the session list ordered by start time.
        Index("ix_sessions_started_at", "started_at"),
        # "Is this court in use?" and the report filtered to one court.
        Index("ix_sessions_court_started", "court_id", "started_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    court_id: Mapped[int] = mapped_column(
        ForeignKey("courts.id", ondelete="RESTRICT"), nullable=False
    )
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    user: Mapped[User] = relationship(back_populates="sessions")
    court: Mapped[Court] = relationship(back_populates="sessions")
    players: Mapped[list["SessionPlayer"]] = relationship(
        back_populates="session", cascade="all, delete-orphan"
    )


class SessionPlayer(Base):
    """One student in a check-in. Tagging a friend adds another row."""

    __tablename__ = "session_players"
    __table_args__ = (
        UniqueConstraint("session_id", "user_id", name="uq_session_player"),
        Index("ix_session_players_user", "user_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    session_id: Mapped[int] = mapped_column(
        ForeignKey("court_sessions.id", ondelete="CASCADE"), nullable=False
    )
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )

    session: Mapped[CourtSession] = relationship(back_populates="players")
    user: Mapped[User] = relationship(back_populates="appearances")

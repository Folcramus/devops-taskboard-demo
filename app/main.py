"""TaskBoard: фронтенд + REST API + PostgreSQL/SQLite."""
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Annotated, Literal
import os

from fastapi import Depends, FastAPI, HTTPException, Response
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import Boolean, DateTime, Integer, String, create_engine, func, select, text
from sqlalchemy.engine import Engine, URL
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker

BASE_DIR = Path(__file__).resolve().parent
PRIORITY = Literal["low", "normal", "high"]

class Base(DeclarativeBase):
    pass

class Task(Base):
    __tablename__ = "tasks"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    title: Mapped[str] = mapped_column(String(160), nullable=False)
    priority: Mapped[str] = mapped_column(String(10), default="normal", nullable=False)
    done: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)

class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=160)
    priority: PRIORITY = "normal"
    @field_validator("title")
    @classmethod
    def non_blank_title(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Название задачи не может быть пустым")
        return value

class TaskPatch(BaseModel):
    done: bool

class TaskRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    title: str
    priority: PRIORITY
    done: bool
    created_at: datetime

class Stats(BaseModel):
    total: int
    completed: int
    active: int

def make_engine() -> Engine:
    """SQLite — для локальной отладки, Postgres — для Docker Compose."""
    explicit = os.getenv("DATABASE_URL")
    if explicit:
        url = explicit
    elif os.getenv("DB_HOST"):
        url = URL.create(
            "postgresql+psycopg",
            username=os.environ.get("DB_USER", "taskboard"),
            password=os.environ["DB_PASSWORD"],
            host=os.environ["DB_HOST"],
            port=5432,
            database=os.environ.get("DB_NAME", "taskboard"),
        )
    else:
        url = f"sqlite+pysqlite:///{BASE_DIR.parent / 'tasks-local.db'}"
    is_sqlite = str(url).startswith("sqlite")
    return create_engine(url, pool_pre_ping=True, connect_args={"check_same_thread": False} if is_sqlite else {})

def create_app(engine: Engine | None = None) -> FastAPI:
    db_engine = engine if engine is not None else make_engine()
    factory = sessionmaker(db_engine, expire_on_commit=False)
    version = os.getenv("APP_VERSION", "local")
    @asynccontextmanager
    async def lifespan(_: FastAPI):
        Base.metadata.create_all(db_engine)
        yield
    api = FastAPI(title="DevOps TaskBoard", version=version, lifespan=lifespan)
    api.mount("/static", StaticFiles(directory=BASE_DIR / "static"), name="static")
    def get_db():
        with factory() as session:
            yield session
    Db = Annotated[Session, Depends(get_db)]
    @api.get("/", include_in_schema=False)
    def homepage():
        return FileResponse(BASE_DIR / "static" / "index.html")
    @api.get("/healthz", tags=["service"])
    def healthz():
        return {"status": "ok", "version": version}
    @api.get("/readyz", tags=["service"])
    def readyz():
        try:
            with db_engine.connect() as conn:
                conn.execute(text("SELECT 1"))
        except SQLAlchemyError:
            return JSONResponse(status_code=503, content={"status": "unavailable"})
        return {"status": "ok", "database": "up", "version": version}
    @api.get("/api/tasks", response_model=list[TaskRead], tags=["tasks"])
    def list_tasks(db: Db):
        return db.scalars(select(Task).order_by(Task.id.desc())).all()
    @api.post("/api/tasks", response_model=TaskRead, status_code=201, tags=["tasks"])
    def add_task(data: TaskCreate, db: Db):
        task = Task(title=data.title, priority=data.priority)
        db.add(task)
        db.commit()
        db.refresh(task)
        return task
    @api.patch("/api/tasks/{task_id}", response_model=TaskRead, tags=["tasks"])
    def toggle_task(task_id: int, data: TaskPatch, db: Db):
        task = db.get(Task, task_id)
        if task is None:
            raise HTTPException(404, "Задача не найдена")
        task.done = data.done
        db.commit()
        db.refresh(task)
        return task
    @api.delete("/api/tasks/{task_id}", status_code=204, tags=["tasks"])
    def remove_task(task_id: int, db: Db):
        task = db.get(Task, task_id)
        if task is None:
            raise HTTPException(404, "Задача не найдена")
        db.delete(task)
        db.commit()
        return Response(status_code=204)
    @api.get("/api/stats", response_model=Stats, tags=["tasks"])
    def stats(db: Db):
        total = db.scalar(select(func.count()).select_from(Task)) or 0
        completed = db.scalar(select(func.count()).select_from(Task).where(Task.done.is_(True))) or 0
        return Stats(total=total, completed=completed, active=total - completed)
    return api

app = create_app()

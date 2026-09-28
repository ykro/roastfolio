"""Worker service. Private on Cloud Run: only Cloud Tasks (OIDC as sa-tasks) can invoke it."""

import re
from functools import lru_cache

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel

from . import pipeline
from .config import settings
from .store import make_store

app = FastAPI(title="roastfolio-worker")
ROAST_ID = re.compile(r"^[A-Za-z0-9_-]{16,40}$")


@lru_cache(maxsize=1)
def get_store():
    return make_store(settings)


class Task(BaseModel):
    roastId: str


@app.get("/healthz")
def healthz():
    return {"ok": True}


@app.post("/internal/process")
def process(task: Task, x_cloudtasks_taskretrycount: int = Header(default=0)):
    if not ROAST_ID.match(task.roastId):
        # Malformed payload: retrying will never help, so acknowledge it.
        return {"ok": False, "reason": "bad roastId"}
    try:
        pipeline.run(task.roastId, get_store(), settings, attempt=x_cloudtasks_taskretrycount)
    except Exception as exc:
        # Non-2xx tells Cloud Tasks to retry with backoff.
        raise HTTPException(status_code=500, detail="retry") from exc
    return {"ok": True}

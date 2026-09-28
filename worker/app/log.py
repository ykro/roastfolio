"""Structured JSON logs. Cloud Run parses each stdout line into jsonPayload."""

import json
import sys
import time
from contextlib import contextmanager


def log(message: str, severity: str = "INFO", **fields) -> None:
    entry = {"severity": severity, "message": message, "component": "worker", **fields}
    print(json.dumps(entry, ensure_ascii=False, default=str), file=sys.stdout, flush=True)


@contextmanager
def step(roast_id: str, name: str):
    """Logs step start/end with durationMs so log-based metrics can chart latency per step."""
    start = time.monotonic()
    log(f"{name} started", roastId=roast_id, step=name, event="step_started")
    try:
        yield
    except Exception as exc:
        ms = int((time.monotonic() - start) * 1000)
        log(f"{name} failed: {exc}", "ERROR", roastId=roast_id, step=name,
            event="step_failed", durationMs=ms)
        raise
    ms = int((time.monotonic() - start) * 1000)
    log(f"{name} finished", roastId=roast_id, step=name, event="step_finished", durationMs=ms)

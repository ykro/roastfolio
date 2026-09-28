"""Persistence for the web service: Firestore docs, `uploads` bucket and the site's index.html.

LocalStore keeps the same interface on disk (LOCAL_MODE=1), shared with the local worker.
"""

import json
import time
from datetime import datetime
from pathlib import Path
from typing import Protocol

from .config import Settings


class Store(Protocol):
    def create(self, roast_id: str, doc: dict) -> None: ...
    def get(self, roast_id: str) -> dict | None: ...
    def put_upload(self, name: str, data: bytes) -> str: ...
    def site_index(self) -> str | None: ...


class GcpStore:
    INDEX_TTL = 60  # seconds; a deploy shows up in /r/{id} within a minute

    def __init__(self, s: Settings):
        from google.cloud import firestore, storage

        self._db = firestore.Client(project=s.project_id, database=s.firestore_db)
        gcs = storage.Client(project=s.project_id)
        self._uploads = gcs.bucket(s.uploads_bucket)
        self._site = gcs.bucket(s.site_bucket)
        self._index: tuple[float, str | None] = (0.0, None)

    def create(self, roast_id, doc):
        self._db.collection("roasts").document(roast_id).create(doc)

    def get(self, roast_id):
        snap = self._db.collection("roasts").document(roast_id).get()
        return snap.to_dict() if snap.exists else None

    def put_upload(self, name, data):
        self._uploads.blob(name).upload_from_string(data, content_type="application/pdf")
        return name

    def site_index(self):
        fetched_at, html = self._index
        if html is None or time.monotonic() - fetched_at > self.INDEX_TTL:
            try:
                html = self._site.blob("index.html").download_as_text()
            except Exception:
                pass  # keep serving the stale copy if GCS hiccups
            self._index = (time.monotonic(), html)
        return html


class LocalStore:
    def __init__(self, s: Settings):
        self._root = Path(s.local_data_dir)
        self._index_path = Path(s.local_index_html)
        for sub in ("roasts", "uploads", "cards"):
            (self._root / sub).mkdir(parents=True, exist_ok=True)

    @property
    def cards_dir(self) -> Path:
        return self._root / "cards"

    def create(self, roast_id, doc):
        (self._root / "roasts" / f"{roast_id}.json").write_text(
            json.dumps(doc, ensure_ascii=False, default=lambda v: v.isoformat() if isinstance(v, datetime) else str(v))
        )

    def get(self, roast_id):
        p = self._root / "roasts" / f"{roast_id}.json"
        return json.loads(p.read_text()) if p.exists() else None

    def put_upload(self, name, data):
        (self._root / "uploads" / name).write_bytes(data)
        return name

    def site_index(self):
        return self._index_path.read_text() if self._index_path.exists() else None


def make_store(s: Settings) -> Store:
    return LocalStore(s) if s.local_mode else GcpStore(s)

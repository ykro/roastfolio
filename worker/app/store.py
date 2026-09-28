"""Persistence: Firestore (roast state) + Cloud Storage (uploads, cards).

LocalStore mirrors the same interface on disk so web and worker can run
together on a laptop without GCP (LOCAL_MODE=1).
"""

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Protocol

from .config import Settings


class Store(Protocol):
    def get(self, roast_id: str) -> dict | None: ...
    def update(self, roast_id: str, **fields) -> None: ...
    def read_upload(self, path: str) -> bytes: ...
    def put_card(self, name: str, data: bytes, content_type: str) -> str: ...


def _now() -> datetime:
    return datetime.now(timezone.utc)


class GcpStore:
    def __init__(self, s: Settings):
        from google.cloud import firestore, storage

        self._db = firestore.Client(project=s.project_id, database=s.firestore_db)
        self._gcs = storage.Client(project=s.project_id)
        self._uploads = self._gcs.bucket(s.uploads_bucket)
        self._cards = self._gcs.bucket(s.cards_bucket)

    def get(self, roast_id):
        snap = self._db.collection("roasts").document(roast_id).get()
        return snap.to_dict() if snap.exists else None

    def update(self, roast_id, **fields):
        self._db.collection("roasts").document(roast_id).update({**fields, "updatedAt": _now()})

    def read_upload(self, path):
        return self._uploads.blob(path).download_as_bytes()

    def put_card(self, name, data, content_type):
        blob = self._cards.blob(name)
        # Short cache: cards die after 24 h and the CDN caps TTL at 1 h anyway.
        blob.cache_control = "public, max-age=3600"
        blob.upload_from_string(data, content_type=content_type)
        return name


class LocalStore:
    def __init__(self, s: Settings):
        self._root = Path(s.local_data_dir)
        for sub in ("roasts", "uploads", "cards"):
            (self._root / sub).mkdir(parents=True, exist_ok=True)

    def _doc(self, roast_id):
        return self._root / "roasts" / f"{roast_id}.json"

    def get(self, roast_id):
        p = self._doc(roast_id)
        return json.loads(p.read_text()) if p.exists() else None

    def update(self, roast_id, **fields):
        doc = self.get(roast_id) or {}
        doc.update(fields, updatedAt=_now().isoformat())
        self._doc(roast_id).write_text(json.dumps(doc, ensure_ascii=False, default=str))

    def read_upload(self, path):
        return (self._root / "uploads" / path).read_bytes()

    def put_card(self, name, data, content_type):
        (self._root / "cards" / name).write_bytes(data)
        return name


def make_store(s: Settings) -> Store:
    return LocalStore(s) if s.local_mode else GcpStore(s)

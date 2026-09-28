"""Web settings, read once from environment variables."""

import os
from dataclasses import dataclass


def _flag(name: str) -> bool:
    return os.getenv(name, "").lower() in ("1", "true", "yes")


@dataclass(frozen=True)
class Settings:
    project_id: str = os.getenv("PROJECT_ID", "ai-experiments-487722")
    firestore_db: str = os.getenv("FIRESTORE_DB", "roastfolio")
    uploads_bucket: str = os.getenv("UPLOADS_BUCKET", "")
    site_bucket: str = os.getenv("SITE_BUCKET", "")
    tasks_location: str = os.getenv("TASKS_LOCATION", "us-central1")
    tasks_queue: str = os.getenv("TASKS_QUEUE", "roasts")
    worker_url: str = os.getenv("WORKER_URL", "http://localhost:8081")
    tasks_sa_email: str = os.getenv("TASKS_SA_EMAIL", "")
    # Absolute origin for og:image, e.g. https://34.1.2.3.nip.io (falls back to the request host).
    public_base_url: str = os.getenv("PUBLIC_BASE_URL", "")
    ttl_hours: int = int(os.getenv("TTL_HOURS", "24"))
    max_pdf_bytes: int = 5 * 1024 * 1024
    max_pdf_pages: int = 5
    # LOCAL_MODE: files under LOCAL_DATA_DIR instead of Firestore/GCS, worker called directly.
    local_mode: bool = _flag("LOCAL_MODE")
    local_data_dir: str = os.getenv("LOCAL_DATA_DIR", "../.localdata")
    local_index_html: str = os.getenv("LOCAL_INDEX_HTML", "../frontend/dist/index.html")


settings = Settings()

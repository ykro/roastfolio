"""Worker settings, read once from environment variables."""

import os
from dataclasses import dataclass


def _flag(name: str) -> bool:
    return os.getenv(name, "").lower() in ("1", "true", "yes")


@dataclass(frozen=True)
class Settings:
    project_id: str = os.getenv("PROJECT_ID", "ai-experiments-487722")
    firestore_db: str = os.getenv("FIRESTORE_DB", "roastfolio")
    uploads_bucket: str = os.getenv("UPLOADS_BUCKET", "")
    cards_bucket: str = os.getenv("CARDS_BUCKET", "")
    docai_location: str = os.getenv("DOCAI_LOCATION", "us")
    docai_processor_id: str = os.getenv("DOCAI_PROCESSOR_ID", "")
    genai_location: str = os.getenv("GENAI_LOCATION", "global")
    text_model: str = os.getenv("GEMINI_TEXT_MODEL", "gemini-3.8-flash")
    image_model: str = os.getenv("GEMINI_IMAGE_MODEL", "gemini-3.1-flash-lite-image")
    thinking_level: str = os.getenv("GEMINI_THINKING_LEVEL", "low")
    apify_actor: str = os.getenv("APIFY_ACTOR", "harvestapi~linkedin-profile-scraper")
    apify_token_secret: str = os.getenv("APIFY_TOKEN_SECRET", "apify-token")
    max_attempts: int = int(os.getenv("MAX_ATTEMPTS", "4"))
    # MOCK_AI: fake Document AI, Apify and Gemini (no cloud calls, deterministic output).
    mock_ai: bool = _flag("MOCK_AI")
    # LOCAL_MODE: Firestore/GCS replaced by files under LOCAL_DATA_DIR (shared with web).
    local_mode: bool = _flag("LOCAL_MODE")
    local_data_dir: str = os.getenv("LOCAL_DATA_DIR", "../.localdata")


settings = Settings()

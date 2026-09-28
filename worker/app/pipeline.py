"""The roast state machine: queued -> extracting -> roasting -> rendering -> done | failed.

Every step saves its output before moving on, so a Cloud Tasks retry resumes
where the previous attempt died instead of paying for Document AI/Gemini again.
"""

from . import ai, card, extract
from .config import Settings
from .errors import PermanentError
from .log import log, step
from .store import Store

GENERIC_ERROR = "Algo salió mal generando tu roast. Intenta de nuevo en unos minutos."


def run(roast_id: str, store: Store, s: Settings, attempt: int = 0) -> None:
    """Processes one roast. Raises only when Cloud Tasks should retry."""
    doc = store.get(roast_id)
    if doc is None:
        log("roast not found (expired?)", "WARNING", roastId=roast_id)
        return
    if doc["status"] in ("done", "failed"):
        log("already finished, skipping", roastId=roast_id, status=doc["status"])
        return

    is_last_attempt = attempt + 1 >= s.max_attempts
    try:
        _run_steps(roast_id, doc, store, s)
    except PermanentError as exc:
        _fail(roast_id, store, exc.user_message, str(exc))
    except Exception as exc:
        if is_last_attempt:
            _fail(roast_id, store, GENERIC_ERROR, f"{type(exc).__name__}: {exc}")
            return
        log("retryable error", "WARNING", roastId=roast_id, attempt=attempt, error=str(exc))
        raise


def _run_steps(roast_id: str, doc: dict, store: Store, s: Settings) -> None:
    text = doc.get("profileText")
    if not text:
        store.update(roast_id, status="extracting")
        with step(roast_id, "extracting"):
            text = extract.extract_text(doc, store.read_upload, s)
        store.update(roast_id, profileText=text)

    result = doc.get("result")
    if not result:
        store.update(roast_id, status="roasting")
        with step(roast_id, "roasting"):
            # Gemini reads the raw CV/LinkedIn text directly: a separate "normalize" call cost ~20 s.
            result = ai.roast(text, doc["intensity"], s)
    # Saving result together with `rendering` lets the UI show the roast while the card renders.
    store.update(roast_id, result=result, status="rendering")

    with step(roast_id, "rendering"):
        raw = ai.card_image(result, doc["intensity"], s)
        card_path = store.put_card(f"{roast_id}.jpg", card.to_og_jpeg(raw), "image/jpeg")

    store.update(roast_id, cardPath=card_path, status="done", error=None)
    log("roast done", roastId=roast_id, step="done", event="roast_done",
        intensity=doc["intensity"], source=doc["source"], score=result["score"])


def _fail(roast_id: str, store: Store, user_message: str, detail: str) -> None:
    store.update(roast_id, status="failed", error=user_message)
    log("roast failed", "ERROR", roastId=roast_id, step="failed", event="roast_failed", error=detail)

"""The roast state machine: queued -> extracting -> roasting -> rendering -> done | failed.

Every step saves its output before moving on, so a Cloud Tasks retry resumes
where the previous attempt died instead of paying for Document AI/Gemini again.
"""

import time

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
        jpeg, generic = _card_or_fallback(roast_id, result, doc["intensity"], s)
        card_path = store.put_card(f"{roast_id}.jpg", jpeg, "image/jpeg")

    store.update(roast_id, cardPath=card_path, cardGeneric=generic, status="done", error=None)
    log("roast done", roastId=roast_id, step="done", event="roast_done",
        intensity=doc["intensity"], source=doc["source"], score=result["score"])


CARD_ATTEMPTS = 2
CARD_RETRY_DELAY_S = 3.0


def _card_or_fallback(roast_id: str, result: dict, intensity: str, s: Settings) -> tuple[bytes, bool]:
    """The roast is already on screen, so a failed image never fails the roast: it gets the generic card.

    Retries in-process instead of through Cloud Tasks, whose backoff would leave the user
    staring at "Imprimiendo tu certificado" for minutes (Vertex image quota 429s come in bursts).
    """
    for attempt in range(1, CARD_ATTEMPTS + 1):
        try:
            return card.to_og_jpeg(ai.card_image(result, intensity, s)), False
        except PermanentError as exc:
            reason = str(exc)
            break
        except Exception as exc:
            reason = f"{type(exc).__name__}: {exc}"
            if attempt < CARD_ATTEMPTS:
                time.sleep(CARD_RETRY_DELAY_S)
    log("generic card used", "WARNING", roastId=roast_id, step="rendering", event="card_fallback", error=reason[:500])
    return card.fallback_jpeg(intensity), True


def _fail(roast_id: str, store: Store, user_message: str, detail: str) -> None:
    store.update(roast_id, status="failed", error=user_message)
    log("roast failed", "ERROR", roastId=roast_id, step="failed", event="roast_failed", error=detail)

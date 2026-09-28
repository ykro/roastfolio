"""Public web service (behind the Load Balancer): the roast API and the /r/{id} share page."""

import html
import json
import re
import secrets
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse

from .config import Settings, settings
from .queue import Queue, make_queue
from .store import Store, make_store
from .validation import INTENSITIES, InvalidInput, check_pdf, normalize_linkedin

ROAST_ID = re.compile(r"^[A-Za-z0-9_-]{16,40}$")
NO_STORE = {"Cache-Control": "no-store"}

FALLBACK_INDEX = """<!doctype html><html lang="es"><head><meta charset="utf-8">
<title>Roastfolio</title></head><body><div id="root"></div></body></html>"""


def log(message: str, severity: str = "INFO", **fields) -> None:
    entry = {"severity": severity, "message": message, "component": "web", **fields}
    print(json.dumps(entry, ensure_ascii=False, default=str), file=sys.stdout, flush=True)


def _as_datetime(value) -> datetime:
    return datetime.fromisoformat(value) if isinstance(value, str) else value


def _is_live(doc: dict | None) -> bool:
    """Logical expiry: Firestore TTL deletes lazily, so we don't wait for it."""
    return bool(doc) and _as_datetime(doc["expiresAt"]) > datetime.now(timezone.utc)


def public_view(roast_id: str, doc: dict) -> dict:
    view = {
        "id": roast_id,
        "status": doc["status"],
        "intensity": doc["intensity"],
        "source": doc["source"],
        "expiresAt": _as_datetime(doc["expiresAt"]).isoformat(),
    }
    if doc.get("result"):
        view["result"] = doc["result"]
    if doc.get("cardPath"):
        view["cardUrl"] = f"/cards/{doc['cardPath']}"
    if doc["status"] == "failed":
        view["error"] = doc.get("error") or "No pudimos generar tu roast."
    return view


OG_STRIP = re.compile(
    r'\s*<meta\s+(?:property="og:[^"]*"|name="twitter:[^"]*"|name="description")[^>]*>', re.IGNORECASE
)


def render_share_page(index: str, meta: dict[str, str]) -> str:
    """Swaps the landing's title/OG tags for the roast's own, keeping Vite's hashed asset tags intact."""
    page = OG_STRIP.sub("", index)
    title = html.escape(meta["title"])
    page = re.sub(r"<title>.*?</title>", f"<title>{title}</title>", page, count=1, flags=re.DOTALL)
    tags = [f'<meta name="description" content="{html.escape(meta["description"])}">']
    for key in ("og:title", "og:description", "og:image", "og:url", "og:type",
                "og:image:width", "og:image:height", "og:site_name"):
        if meta.get(key):
            tags.append(f'<meta property="{key}" content="{html.escape(meta[key])}">')
    tags.append('<meta name="twitter:card" content="summary_large_image">')
    if meta.get("og:image"):
        tags.append(f'<meta name="twitter:image" content="{html.escape(meta["og:image"])}">')
    return page.replace("</head>", "  " + "\n  ".join(tags) + "\n</head>", 1)


def create_app(store: Store | None = None, queue: Queue | None = None, s: Settings = settings) -> FastAPI:
    app = FastAPI(title="roastfolio-web", docs_url=None, redoc_url=None)
    state = {"store": store, "queue": queue}

    def get_store() -> Store:
        if state["store"] is None:
            state["store"] = make_store(s)
        return state["store"]

    def get_queue() -> Queue:
        if state["queue"] is None:
            state["queue"] = make_queue(s)
        return state["queue"]

    def base_url(request: Request) -> str:
        if s.public_base_url:
            return s.public_base_url.rstrip("/")
        proto = request.headers.get("x-forwarded-proto", request.url.scheme)
        return f"{proto}://{request.headers.get('host', request.url.netloc)}"

    @app.exception_handler(InvalidInput)
    async def invalid_input(_: Request, exc: InvalidInput):
        return JSONResponse({"detail": str(exc)}, status_code=400)

    @app.get("/api/health")
    def health():
        return {"ok": True}

    @app.post("/api/roasts", status_code=201)
    async def create_roast(
        intensity: str = Form(...),
        consent: bool = Form(False),
        url: str | None = Form(None),
        pdf: UploadFile | None = File(None),
    ):
        if intensity not in INTENSITIES:
            raise InvalidInput("Intensidad inválida.")
        if not consent:
            raise InvalidInput("Confirma que es tu perfil o que tienes permiso para roastearlo.")
        has_pdf = pdf is not None and pdf.filename
        if bool(has_pdf) == bool(url and url.strip()):
            raise InvalidInput("Sube un PDF o pega una URL de LinkedIn (solo una de las dos).")

        roast_id = secrets.token_urlsafe(16)
        now = datetime.now(timezone.utc)
        if has_pdf:
            data = await pdf.read(s.max_pdf_bytes + 1)
            pages = check_pdf(data, s.max_pdf_bytes, s.max_pdf_pages)
            source, source_ref = "pdf", get_store().put_upload(f"{roast_id}.pdf", data)
        else:
            pages = None
            source, source_ref = "url", normalize_linkedin(url)

        get_store().create(roast_id, {
            "status": "queued",
            "source": source,
            "sourceRef": source_ref,
            "intensity": intensity,
            "profileText": None,
            "result": None,
            "cardPath": None,
            "error": None,
            "createdAt": now,
            "updatedAt": now,
            "expiresAt": now + timedelta(hours=s.ttl_hours),  # Firestore TTL policy field
        })
        get_queue().enqueue(roast_id)
        log("roast queued", roastId=roast_id, step="queued", event="roast_queued",
            source=source, intensity=intensity, pages=pages)
        return JSONResponse({"id": roast_id}, status_code=201, headers=NO_STORE)

    @app.get("/api/roasts/{roast_id}")
    def get_roast(roast_id: str):
        doc = get_store().get(roast_id) if ROAST_ID.match(roast_id) else None
        if not _is_live(doc):
            return JSONResponse({"detail": "expired"}, status_code=404, headers=NO_STORE)
        return JSONResponse(public_view(roast_id, doc), headers=NO_STORE)

    @app.get("/r/{roast_id}", response_class=HTMLResponse)
    def share_page(roast_id: str, request: Request):
        doc = get_store().get(roast_id) if ROAST_ID.match(roast_id) else None
        index = get_store().site_index() or FALLBACK_INDEX
        origin = base_url(request)
        if not _is_live(doc):
            meta = {"title": "Este roast ya expiró · Roastfolio",
                    "description": "Los roasts de Roastfolio se borran a las 24 horas. Haz el tuyo.",
                    "og:title": "Este roast ya expiró",
                    "og:description": "Los roasts de Roastfolio se borran a las 24 horas. Haz el tuyo.",
                    "og:site_name": "Roastfolio", "og:type": "website"}
            return HTMLResponse(render_share_page(index, meta), status_code=404, headers=NO_STORE)

        result = doc.get("result") or {}
        title = f"{result['name']}: {result['headline']}" if result else "Un roast en el horno"
        description = (f"Calificación {result['score']}/10. Mira el roast completo antes de que se borre en 24 horas."
                       if result else "Roastfolio está cocinando este perfil.")
        meta = {"title": f"{title} · Roastfolio", "description": description,
                "og:title": title, "og:description": description,
                "og:url": f"{origin}/r/{roast_id}", "og:type": "website", "og:site_name": "Roastfolio"}
        if doc.get("cardPath"):
            meta |= {"og:image": f"{origin}/cards/{doc['cardPath']}",
                     "og:image:width": "1200", "og:image:height": "630"}
        # Short cache: the page changes from "cooking" to the final roast within a minute.
        cache = "public, max-age=300" if doc["status"] == "done" else "no-store"
        return HTMLResponse(render_share_page(index, meta), headers={"Cache-Control": cache})

    if s.local_mode:
        # On GCP the Load Balancer maps /cards/* to the cards bucket; locally web serves them.
        @app.get("/cards/{name}")
        def local_card(name: str):
            path = Path(s.local_data_dir) / "cards" / Path(name).name
            if not path.exists():
                raise HTTPException(404)
            return FileResponse(path, media_type="image/jpeg")

    return app


app = create_app()

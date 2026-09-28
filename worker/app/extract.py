"""Step 1 (extracting): PDF -> Document AI Layout Parser, LinkedIn URL -> Apify. Output: plain text."""

import json
import re
from functools import lru_cache

import httpx

from .config import Settings
from .errors import PermanentError

MAX_CHARS = 30_000
APIFY_FIELDS = (
    "firstName", "lastName", "headline", "about", "location", "experience",
    "education", "skills", "topSkills", "certifications", "projects", "languages",
    "honorsAndAwards", "volunteering",
)


def _flatten_blocks(blocks, out: list[str]) -> None:
    """Walks the Layout Parser tree (text, table and list blocks can nest)."""
    for b in blocks:
        if b.text_block and (b.text_block.text or b.text_block.blocks):
            if b.text_block.text:
                out.append(b.text_block.text)
            _flatten_blocks(b.text_block.blocks, out)
        elif b.table_block and (b.table_block.header_rows or b.table_block.body_rows):
            for row in [*b.table_block.header_rows, *b.table_block.body_rows]:
                cells = []
                for cell in row.cells:
                    parts: list[str] = []
                    _flatten_blocks(cell.blocks, parts)
                    cells.append(" ".join(parts))
                out.append(" | ".join(cells))
        elif b.list_block and b.list_block.list_entries:
            for entry in b.list_block.list_entries:
                parts = []
                _flatten_blocks(entry.blocks, parts)
                out.append("- " + " ".join(parts))


def pdf_to_text(pdf: bytes, s: Settings) -> str:
    from google.api_core import exceptions as gexc
    from google.cloud import documentai

    client = documentai.DocumentProcessorServiceClient(
        client_options={"api_endpoint": f"{s.docai_location}-documentai.googleapis.com"}
    )
    name = client.processor_path(s.project_id, s.docai_location, s.docai_processor_id)
    request = documentai.ProcessRequest(
        name=name,
        raw_document=documentai.RawDocument(content=pdf, mime_type="application/pdf"),
    )
    try:
        doc = client.process_document(request=request).document
    except gexc.InvalidArgument as exc:
        raise PermanentError("No pudimos leer el PDF. ¿Está dañado o protegido?", str(exc)) from exc

    parts: list[str] = []
    _flatten_blocks(doc.document_layout.blocks, parts)
    text = "\n".join(p.strip() for p in parts if p.strip()) or doc.text
    if len(text.strip()) < 80:
        raise PermanentError("El PDF casi no tiene texto. Prueba con un CV exportado, no escaneado.")
    return text[:MAX_CHARS]


@lru_cache(maxsize=1)
def _apify_token(project_id: str, secret: str) -> str:
    from google.cloud import secretmanager

    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project_id}/secrets/{secret}/versions/latest"
    return client.access_secret_version(name=name).payload.data.decode().strip()


def linkedin_to_text(url: str, s: Settings) -> str:
    token = _apify_token(s.project_id, s.apify_token_secret)
    resp = httpx.post(
        f"https://api.apify.com/v2/acts/{s.apify_actor}/run-sync-get-dataset-items",
        headers={"Authorization": f"Bearer {token}"},
        json={"urls": [url]},
        timeout=180,
    )
    resp.raise_for_status()  # 5xx / auth / quota -> retryable
    items = resp.json()
    item = items[0] if isinstance(items, list) and items else None
    if not item or not (item.get("firstName") or item.get("experience")):
        raise PermanentError("No encontramos ese perfil de LinkedIn o no es público.")
    trimmed = {k: _prune(item[k]) for k in APIFY_FIELDS if item.get(k)}
    return json.dumps(trimmed, ensure_ascii=False)[:MAX_CHARS]


_NOISE = re.compile(r"(url|urn|logo|picture|photo|id)$", re.IGNORECASE)


def _prune(value):
    """Drops logos, URLs, ids and empty values: fewer tokens, same meaning for the model."""
    if isinstance(value, dict):
        out = {k: _prune(v) for k, v in value.items() if not _NOISE.search(k)}
        return {k: v for k, v in out.items() if v not in (None, "", [], {})}
    if isinstance(value, list):
        return [p for p in (_prune(v) for v in value) if p not in (None, "", [], {})]
    return value


def extract_text(doc: dict, pdf_loader, s: Settings) -> str:
    if s.mock_ai:
        return MOCK_TEXT
    if doc["source"] == "pdf":
        return pdf_to_text(pdf_loader(doc["sourceRef"]), s)
    return linkedin_to_text(doc["sourceRef"], s)


MOCK_TEXT = """María Fernanda López
Chief Synergy Officer & Thought Leader | Apasionada por la disrupción
Experiencia: Ninja de Innovación en StartupX (2022-2024), 3 meses.
Gurú de Transformación Digital en Consultora Y (2021-2022).
Educación: Licenciatura en Administración, Universidad Galileo (2020).
Skills: Liderazgo, Sinergia, Blockchain, Excel, Trabajo en equipo, Microsoft Word."""

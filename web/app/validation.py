"""Input checks for POST /api/roasts. Messages are shown to the user as-is (Spanish)."""

import io
import re

from pypdf import PdfReader
from pypdf.errors import PdfReadError

INTENSITIES = ("soft", "medium", "brutal")
LINKEDIN = re.compile(
    r"^(?:https?://)?(?:[a-z]{2,3}\.)?(?:www\.)?linkedin\.com/in/([A-Za-z0-9\-_%.]{3,100})/?(?:[?#].*)?$",
    re.IGNORECASE,
)


class InvalidInput(ValueError):
    pass


def check_pdf(data: bytes, max_bytes: int, max_pages: int) -> int:
    if len(data) > max_bytes:
        raise InvalidInput(f"El PDF pesa más de {max_bytes // (1024 * 1024)} MB.")
    if not data.startswith(b"%PDF"):
        raise InvalidInput("El archivo no es un PDF.")
    try:
        reader = PdfReader(io.BytesIO(data))
        if reader.is_encrypted and not reader.decrypt(""):
            raise InvalidInput("El PDF está protegido con contraseña.")
        pages = len(reader.pages)
    except (PdfReadError, ValueError, KeyError) as exc:
        if isinstance(exc, InvalidInput):
            raise
        raise InvalidInput("No pudimos abrir el PDF. ¿Está dañado?") from exc
    if pages > max_pages:
        raise InvalidInput(f"El PDF tiene {pages} páginas; el máximo es {max_pages}.")
    return pages


def normalize_linkedin(url: str) -> str:
    m = LINKEDIN.match(url.strip())
    if not m:
        raise InvalidInput("La URL debe ser de un perfil de LinkedIn, por ejemplo linkedin.com/in/tu-usuario.")
    return f"https://www.linkedin.com/in/{m.group(1)}/"

"""Card post-processing: Nano Banana output -> 1200x630 JPEG, light enough for social previews."""

import io
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

OG_SIZE = (1200, 630)
MAX_BYTES = 300 * 1024  # WhatsApp and friends skip previews for heavy images


def to_og_jpeg(raw: bytes) -> bytes:
    img = Image.open(io.BytesIO(raw)).convert("RGB")
    img = ImageOps.fit(img, OG_SIZE, method=Image.Resampling.LANCZOS)
    for quality in (85, 75, 65, 55):
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=quality, optimize=True, progressive=True)
        if buf.tell() <= MAX_BYTES:
            break
    return buf.getvalue()


ASSETS = Path(__file__).parent / "assets"


def fallback_jpeg(intensity: str) -> bytes:
    """Pre-generated generic certificate (same style per intensity) for when Nano Banana fails."""
    return (ASSETS / f"fallback-{intensity}.jpg").read_bytes()


def _font(size: int):
    for name in ("DejaVuSerif-Bold.ttf", "Georgia Bold.ttf", "/System/Library/Fonts/Supplemental/Georgia Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default(size)


def mock_card(result: dict, intensity: str) -> bytes:
    """Stand-in certificate for MOCK_AI runs (no image model call)."""
    bg = {"soft": "#f3e9d2", "medium": "#e9e4d8", "brutal": "#2b1d17"}[intensity]
    ink = "#2b1d17" if intensity != "brutal" else "#f3e9d2"
    img = Image.new("RGB", (1344, 768), bg)
    d = ImageDraw.Draw(img)
    d.rectangle((40, 40, 1304, 728), outline="#b08d3c", width=8)
    lines = [
        ("CERTIFICADO OFICIAL DE ROAST", 54, 130),
        ("Otorgado a", 28, 230),
        (result["name"], 48, 290),
        (result["headline"], 40, 400),
        (f"{result['score']}/10", 64, 540),
        ("Roastfolio · Válido por 24 horas", 24, 680),
    ]
    for text, size, y in lines:
        font = _font(size)
        w = d.textlength(text, font=font)
        d.text(((1344 - w) / 2, y), text, fill=ink, font=font)
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return buf.getvalue()

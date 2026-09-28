import io
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from pypdf import PdfWriter
from pypdf.errors import ParseError

from app import validation
from app.config import Settings
from app.main import create_app, render_share_page
from app.validation import InvalidInput, normalize_linkedin

INDEX = """<!doctype html><html><head><meta charset="utf-8"><title>Roastfolio</title>
<meta name="description" content="landing"><meta property="og:title" content="Roastfolio">
<script type="module" src="/assets/index-abc123.js"></script></head><body><div id="root"></div></body></html>"""


class FakeStore:
    def __init__(self):
        self.docs, self.uploads = {}, {}

    def create(self, rid, doc):
        assert rid not in self.docs
        self.docs[rid] = doc

    def get(self, rid):
        return self.docs.get(rid)

    def put_upload(self, name, data):
        self.uploads[name] = data
        return name

    def site_index(self):
        return INDEX


class FakeQueue:
    def __init__(self):
        self.ids = []

    def enqueue(self, rid):
        self.ids.append(rid)


def make_pdf(pages: int) -> bytes:
    w = PdfWriter()
    for _ in range(pages):
        w.add_blank_page(width=612, height=792)
    buf = io.BytesIO()
    w.write(buf)
    return buf.getvalue()


@pytest.fixture
def env():
    store, queue = FakeStore(), FakeQueue()
    s = Settings(public_base_url="https://1.2.3.4.nip.io")
    return TestClient(create_app(store, queue, s)), store, queue


def post(client, data=None, files=None):
    return client.post("/api/roasts", data={"intensity": "brutal", "consent": "true", **(data or {})}, files=files)


def test_pdf_roast_is_stored_and_queued(env):
    client, store, queue = env
    r = post(client, files={"pdf": ("cv.pdf", make_pdf(2), "application/pdf")})
    assert r.status_code == 201
    rid = r.json()["id"]
    doc = store.docs[rid]
    assert doc["status"] == "queued" and doc["source"] == "pdf" and doc["sourceRef"] == f"{rid}.pdf"
    assert doc["expiresAt"] - doc["createdAt"] == timedelta(hours=24)
    assert queue.ids == [rid]
    assert len(rid) >= 20  # unguessable: cards bucket is public


def test_url_roast_is_normalized(env):
    client, store, _ = env
    r = post(client, data={"url": "linkedin.com/in/ykro?trk=abc"})
    assert r.status_code == 201
    assert store.docs[r.json()["id"]]["sourceRef"] == "https://www.linkedin.com/in/ykro/"


@pytest.mark.parametrize("data,files,msg", [
    ({"intensity": "extreme", "url": "https://linkedin.com/in/ykro"}, None, "Intensidad"),
    ({"consent": "false", "url": "https://linkedin.com/in/ykro"}, None, "permiso"),
    ({}, None, "solo una"),
    ({"url": "https://twitter.com/ykro"}, None, "LinkedIn"),
    ({}, {"pdf": ("cv.pdf", b"hello", "application/pdf")}, "no es un PDF"),
])
def test_invalid_inputs(env, data, files, msg):
    client, _, queue = env
    r = post(client, data=data, files=files)
    assert r.status_code == 400 and msg in r.json()["detail"]
    assert queue.ids == []


def test_pdf_limits(env):
    client, _, _ = env
    r = post(client, files={"pdf": ("cv.pdf", make_pdf(6), "application/pdf")})
    assert r.status_code == 400 and "6 páginas" in r.json()["detail"]
    big = b"%PDF-1.4\n" + b"0" * (5 * 1024 * 1024 + 1)
    r = post(client, files={"pdf": ("cv.pdf", big, "application/pdf")})
    assert r.status_code == 400 and "5 MB" in r.json()["detail"]


@pytest.mark.parametrize("exc", [ParseError("bad xref"), IndexError("list index"), TypeError("NoneType")])
def test_broken_pdf_is_a_400_not_a_500(env, monkeypatch, exc):
    def explode(*a, **k):
        raise exc

    monkeypatch.setattr(validation, "PdfReader", explode)
    client, _, _ = env
    r = post(client, files={"pdf": ("cv.pdf", make_pdf(1), "application/pdf")})
    assert r.status_code == 400 and "dañado" in r.json()["detail"]


def test_both_inputs_rejected(env):
    client, _, _ = env
    r = post(client, data={"url": "https://linkedin.com/in/ykro"},
             files={"pdf": ("cv.pdf", make_pdf(1), "application/pdf")})
    assert r.status_code == 400


def seed(store, rid="r" * 22, **kw):
    now = datetime.now(timezone.utc)
    store.docs[rid] = {"status": "done", "source": "url", "sourceRef": "x", "intensity": "soft",
                       "result": {"name": "Ana <b>", "headline": "Sinergia sin evidencia", "roast": "...",
                                  "score": 4, "tips": []},
                       "cardPath": f"{rid}.jpg", "error": None, "createdAt": now,
                       "expiresAt": now + timedelta(hours=1), **kw}
    return rid


def test_get_roast_done(env):
    client, store, _ = env
    rid = seed(store)
    r = client.get(f"/api/roasts/{rid}")
    body = r.json()
    assert r.status_code == 200 and r.headers["cache-control"] == "no-store"
    assert body["cardUrl"] == f"/cards/{rid}.jpg" and body["result"]["score"] == 4
    assert body["cardGeneric"] is False
    assert "profileText" not in body and "sourceRef" not in body


def test_get_roast_flags_generic_card(env):
    client, store, _ = env
    rid = seed(store, cardGeneric=True)
    assert client.get(f"/api/roasts/{rid}").json()["cardGeneric"] is True


def test_expired_roast_is_gone_even_before_ttl_deletes_it(env):
    client, store, _ = env
    rid = seed(store, expiresAt=datetime.now(timezone.utc) - timedelta(minutes=1))
    assert client.get(f"/api/roasts/{rid}").status_code == 404
    page = client.get(f"/r/{rid}")
    assert page.status_code == 404 and "Este roast ya expiró" in page.text


def test_unknown_and_malformed_ids(env):
    client, _, _ = env
    assert client.get("/api/roasts/nope").status_code == 404
    assert client.get("/api/roasts/" + "x" * 22).status_code == 404


def test_share_page_has_og_tags_and_keeps_assets(env):
    client, store, _ = env
    rid = seed(store)
    page = client.get(f"/r/{rid}").text
    assert f'<meta property="og:image" content="https://1.2.3.4.nip.io/cards/{rid}.jpg">' in page
    assert "Ana &lt;b&gt;: Sinergia sin evidencia" in page  # escaped
    assert "/assets/index-abc123.js" in page
    assert page.count('property="og:title"') == 1  # landing tag replaced, not duplicated
    assert "landing" not in page


def test_share_page_while_cooking_has_no_image(env):
    client, store, _ = env
    rid = seed(store, status="roasting", result=None, cardPath=None)
    r = client.get(f"/r/{rid}")
    assert r.status_code == 200 and "og:image" not in r.text and r.headers["cache-control"] == "no-store"


def test_normalize_linkedin_variants():
    assert normalize_linkedin("https://gt.linkedin.com/in/ana-lopez-123/") == "https://www.linkedin.com/in/ana-lopez-123/"
    with pytest.raises(InvalidInput):
        normalize_linkedin("https://linkedin.com/company/google")


def test_render_share_page_without_head_tags():
    out = render_share_page("<html><head><title>x</title></head></html>", {"title": "T", "description": "D"})
    assert "<title>T</title>" in out and 'name="description" content="D"' in out

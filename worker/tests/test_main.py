from fastapi.testclient import TestClient

from app import main


class Boom:
    def get(self, rid):
        raise RuntimeError("firestore down")


def test_bad_id_is_acknowledged():
    r = TestClient(main.app).post("/internal/process", json={"roastId": "../etc"})
    assert r.status_code == 200 and r.json()["ok"] is False


def test_retryable_error_returns_500(monkeypatch):
    monkeypatch.setattr(main, "get_store", lambda: Boom())
    r = TestClient(main.app).post(
        "/internal/process", json={"roastId": "abc123abc123abc123"},
        headers={"X-CloudTasks-TaskRetryCount": "1"},
    )
    assert r.status_code == 500

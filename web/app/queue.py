"""Enqueues the pipeline. Cloud Tasks delivers to the private worker with an OIDC token (sa-tasks)."""

import json
import threading
from typing import Protocol

import httpx

from .config import Settings


class Queue(Protocol):
    def enqueue(self, roast_id: str) -> None: ...


class CloudTasksQueue:
    def __init__(self, s: Settings):
        from google.cloud import tasks_v2

        self._tasks_v2 = tasks_v2
        self._client = tasks_v2.CloudTasksClient()
        self._parent = self._client.queue_path(s.project_id, s.tasks_location, s.tasks_queue)
        self._s = s

    def enqueue(self, roast_id):
        tv = self._tasks_v2
        url = self._s.worker_url.rstrip("/")
        task = tv.Task(
            # Named after the roast: Cloud Tasks rejects duplicates, so a double submit can't run twice.
            name=f"{self._parent}/tasks/{roast_id}",
            http_request=tv.HttpRequest(
                http_method=tv.HttpMethod.POST,
                url=f"{url}/internal/process",
                headers={"Content-Type": "application/json"},
                body=json.dumps({"roastId": roast_id}).encode(),
                oidc_token=tv.OidcToken(service_account_email=self._s.tasks_sa_email, audience=url),
            ),
            dispatch_deadline={"seconds": 600},
        )
        self._client.create_task(parent=self._parent, task=task)


class LocalQueue:
    """Laptop stand-in: calls the local worker in a background thread, like a single-attempt queue."""

    def __init__(self, s: Settings):
        self._url = s.worker_url.rstrip("/") + "/internal/process"

    def enqueue(self, roast_id):
        threading.Thread(
            target=lambda: httpx.post(self._url, json={"roastId": roast_id}, timeout=600), daemon=True
        ).start()


def make_queue(s: Settings) -> Queue:
    return LocalQueue(s) if s.local_mode else CloudTasksQueue(s)

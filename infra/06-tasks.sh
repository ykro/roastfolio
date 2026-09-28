#!/usr/bin/env bash
# Cloud Tasks queue: bounded concurrency (protects Vertex quotas) and 4 attempts (1 + 3 retries).
source "$(dirname "$0")/env.sh"

FLAGS=(--location="$REGION" --max-concurrent-dispatches=5 --max-dispatches-per-second=2
       --max-attempts=4 --min-backoff=10s --max-backoff=120s --max-doublings=3)

say "Queue '$QUEUE'"
if exists gcloud tasks queues describe "$QUEUE" --location="$REGION"; then
  gcloud tasks queues update "$QUEUE" "${FLAGS[@]}"
else
  gcloud tasks queues create "$QUEUE" "${FLAGS[@]}"
fi

say "sa-web can enqueue (queue-level role)"
gcloud tasks queues add-iam-policy-binding "$QUEUE" --location="$REGION" \
  --member="serviceAccount:$SA_WEB" --role=roles/cloudtasks.enqueuer >/dev/null
echo "  done"

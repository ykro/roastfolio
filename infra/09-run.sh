#!/usr/bin/env bash
# First deploy of both Cloud Run services with their full configuration.
# Afterwards Cloud Build only swaps the image; runtime config stays here.
# Usage: infra/09-run.sh            (builds images from the local tree)
#        SKIP_BUILD=1 infra/09-run.sh (reuses :latest)
source "$(dirname "$0")/env.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCAI_PROCESSOR_ID="$(cat "$GEN_DIR/docai-processor-id")"

if [[ -z "${SKIP_BUILD:-}" ]]; then
  say "Building images with Cloud Build"
  gcloud builds submit "$ROOT/worker" --tag="$AR/worker:latest" --region="$REGION" --quiet
  gcloud builds submit "$ROOT/web" --tag="$AR/web:latest" --region="$REGION" --quiet
fi

say "Worker: private, internal ingress, invoked only by Cloud Tasks"
# Cloud Tasks traffic counts as internal, so nothing on the internet can even reach the URL.
gcloud run deploy "$WORKER_SERVICE" --image="$AR/worker:latest" --region="$REGION" \
  --service-account="$SA_WORKER" --no-allow-unauthenticated --ingress=internal \
  --cpu=1 --memory=1Gi --concurrency=4 --max-instances=5 --timeout=600 \
  --set-env-vars="PROJECT_ID=$PROJECT_ID,FIRESTORE_DB=$FIRESTORE_DB,UPLOADS_BUCKET=$UPLOADS_BUCKET,CARDS_BUCKET=$CARDS_BUCKET,DOCAI_LOCATION=$DOCAI_LOCATION,DOCAI_PROCESSOR_ID=$DOCAI_PROCESSOR_ID,GENAI_LOCATION=global,GEMINI_TEXT_MODEL=gemini-3.8-flash,GEMINI_IMAGE_MODEL=gemini-3.1-flash-lite-image,APIFY_TOKEN_SECRET=$APIFY_SECRET,MAX_ATTEMPTS=4" \
  --quiet
WORKER_URL="$(gcloud run services describe "$WORKER_SERVICE" --region="$REGION" --format='value(status.url)')"

say "sa-tasks may invoke the worker (and nothing else)"
gcloud run services add-iam-policy-binding "$WORKER_SERVICE" --region="$REGION" \
  --member="serviceAccount:$SA_TASKS" --role=roles/run.invoker --quiet >/dev/null

say "Web: reachable only through the Load Balancer"
# internal-and-cloud-load-balancing blocks the *.run.app URL from the internet;
# --no-invoker-iam-check lets anonymous users in once they come through the LB.
PUBLIC_BASE_URL="$(cat "$GEN_DIR/public-base-url" 2>/dev/null || true)"
gcloud run deploy "$WEB_SERVICE" --image="$AR/web:latest" --region="$REGION" \
  --service-account="$SA_WEB" --ingress=internal-and-cloud-load-balancing --no-invoker-iam-check \
  --cpu=1 --memory=512Mi --concurrency=40 --max-instances=5 --timeout=60 \
  --set-env-vars="PROJECT_ID=$PROJECT_ID,FIRESTORE_DB=$FIRESTORE_DB,UPLOADS_BUCKET=$UPLOADS_BUCKET,SITE_BUCKET=$SITE_BUCKET,TASKS_LOCATION=$REGION,TASKS_QUEUE=$QUEUE,WORKER_URL=$WORKER_URL,TASKS_SA_EMAIL=$SA_TASKS,PUBLIC_BASE_URL=$PUBLIC_BASE_URL" \
  --quiet
echo "  worker: $WORKER_URL"

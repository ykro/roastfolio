#!/usr/bin/env bash
# Shared settings for every infra script. Source it: `source infra/env.sh`.
set -euo pipefail

export PROJECT_ID="${PROJECT_ID:-ai-experiments-487722}"
export REGION="${REGION:-us-central1}"
export CLOUDSDK_CORE_PROJECT="$PROJECT_ID"  # scope gcloud without touching the global config
export PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"

export APP=roastfolio
export SITE_BUCKET="${PROJECT_ID}-${APP}-site"
export UPLOADS_BUCKET="${PROJECT_ID}-${APP}-uploads"
export CARDS_BUCKET="${PROJECT_ID}-${APP}-cards"
export FIRESTORE_DB="$APP"
export QUEUE=roasts
export AR_REPO="$APP"
export AR="${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO}"
export WEB_SERVICE="${APP}-web"
export WORKER_SERVICE="${APP}-worker"
export DOCAI_LOCATION=us
export DOCAI_PROCESSOR_NAME="${APP}-layout"
export APIFY_SECRET=apify-token
export ALERT_EMAIL="${ALERT_EMAIL:-aacs85@gmail.com}"

export SA_WEB="sa-web@${PROJECT_ID}.iam.gserviceaccount.com"
export SA_WORKER="sa-worker@${PROJECT_ID}.iam.gserviceaccount.com"
export SA_TASKS="sa-tasks@${PROJECT_ID}.iam.gserviceaccount.com"
export SA_BUILD="sa-build@${PROJECT_ID}.iam.gserviceaccount.com"

# Load balancer pieces
export LB_IP_NAME=rf-ip
export LB_NEG=rf-web-neg
export LB_WEB_BACKEND=rf-web-backend
export LB_SITE_BACKEND=rf-site-backend
export LB_CARDS_BACKEND=rf-cards-backend
export LB_URL_MAP=rf-url-map
export LB_CERT=rf-cert
export LB_HTTPS_PROXY=rf-https-proxy
export LB_HTTPS_RULE=rf-https-rule
export LB_REDIRECT_MAP=rf-http-redirect
export LB_HTTP_PROXY=rf-http-proxy
export LB_HTTP_RULE=rf-http-rule
export ARMOR_POLICY=rf-armor

GEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.generated"
mkdir -p "$GEN_DIR"
export GEN_DIR

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
exists() { "$@" >/dev/null 2>&1; }

#!/usr/bin/env bash
# The only API key in the system (Apify) lives in Secret Manager; only sa-worker can read it.
# Create it first (the token never touches a file):
#   printf '%s' 'apify_api_...' | gcloud secrets create apify-token --data-file=- --replication-policy=automatic
# Rotate it:
#   printf '%s' 'apify_api_...' | gcloud secrets versions add apify-token --data-file=-
source "$(dirname "$0")/env.sh"

say "Secret '$APIFY_SECRET'"
if ! exists gcloud secrets describe "$APIFY_SECRET"; then
  echo "  Missing. Create it with the command at the top of this script." >&2
  exit 1
fi
gcloud secrets add-iam-policy-binding "$APIFY_SECRET" \
  --member="serviceAccount:$SA_WORKER" --role=roles/secretmanager.secretAccessor >/dev/null
echo "  sa-worker can read it"

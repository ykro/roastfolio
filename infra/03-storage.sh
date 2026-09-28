#!/usr/bin/env bash
# Three buckets: site (public, CDN), uploads (private, 1-day lifecycle), cards (public, CDN, 1-day lifecycle).
source "$(dirname "$0")/env.sh"

LIFECYCLE="$GEN_DIR/lifecycle-1d.json"
cat > "$LIFECYCLE" <<JSON
{"rule": [{"action": {"type": "Delete"}, "condition": {"age": 1}}]}
JSON

make_bucket() {
  local b=$1
  if ! exists gcloud storage buckets describe "gs://$b"; then
    gcloud storage buckets create "gs://$b" --location="$REGION" --uniform-bucket-level-access
  fi
}

say "Buckets"
make_bucket "$SITE_BUCKET"
make_bucket "$UPLOADS_BUCKET"
make_bucket "$CARDS_BUCKET"

# Anyone may GET an object by name, nobody may list: objectViewer would expose every roast id
# in cards (and each id opens its roast through the API).
public_read() {
  gcloud storage buckets add-iam-policy-binding "$1" --member=allUsers --role=roles/storage.legacyObjectReader >/dev/null
  gcloud storage buckets remove-iam-policy-binding "$1" --member=allUsers --role=roles/storage.objectViewer >/dev/null 2>&1 || true
}

say "uploads: private + lifecycle"
gcloud storage buckets update "gs://$UPLOADS_BUCKET" --public-access-prevention --lifecycle-file="$LIFECYCLE"
gcloud storage buckets add-iam-policy-binding "gs://$UPLOADS_BUCKET" \
  --member="serviceAccount:$SA_WEB" --role=roles/storage.objectCreator >/dev/null
gcloud storage buckets add-iam-policy-binding "gs://$UPLOADS_BUCKET" \
  --member="serviceAccount:$SA_WORKER" --role=roles/storage.objectViewer >/dev/null

say "cards: public read by name (backend buckets need it) + lifecycle"
gcloud storage buckets update "gs://$CARDS_BUCKET" --lifecycle-file="$LIFECYCLE"
public_read "gs://$CARDS_BUCKET"
# objectUser (not objectCreator) so a retried task can overwrite a half-written card.
gcloud storage buckets add-iam-policy-binding "gs://$CARDS_BUCKET" \
  --member="serviceAccount:$SA_WORKER" --role=roles/storage.objectUser >/dev/null

say "site: public read, Cloud Build writes"
public_read "gs://$SITE_BUCKET"
gcloud storage buckets add-iam-policy-binding "gs://$SITE_BUCKET" \
  --member="serviceAccount:$SA_BUILD" --role=roles/storage.objectAdmin >/dev/null
echo "  done"

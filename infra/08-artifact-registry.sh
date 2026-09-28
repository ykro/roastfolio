#!/usr/bin/env bash
# Docker repository for web and worker images, with a cleanup policy so it doesn't grow forever.
source "$(dirname "$0")/env.sh"

say "Artifact Registry '$AR_REPO'"
if ! exists gcloud artifacts repositories describe "$AR_REPO" --location="$REGION"; then
  gcloud artifacts repositories create "$AR_REPO" --repository-format=docker --location="$REGION" \
    --description="Roastfolio images"
fi

cat > "$GEN_DIR/ar-cleanup.json" <<JSON
[
  {"name": "keep-recent", "action": {"type": "Keep"}, "mostRecentVersions": {"keepCount": 10}},
  {"name": "delete-old", "action": {"type": "Delete"}, "condition": {"olderThan": "30d"}}
]
JSON
gcloud artifacts repositories set-cleanup-policies "$AR_REPO" --location="$REGION" \
  --policy="$GEN_DIR/ar-cleanup.json" --no-dry-run --quiet >/dev/null

gcloud artifacts repositories add-iam-policy-binding "$AR_REPO" --location="$REGION" \
  --member="serviceAccount:$SA_BUILD" --role=roles/artifactregistry.writer >/dev/null
echo "  done"

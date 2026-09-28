#!/usr/bin/env bash
# One service account per component, project-level roles only where no finer scope exists.
# Resource-level grants (buckets, queue, secret, worker service, AR repo) live in the script
# that creates each resource.
source "$(dirname "$0")/env.sh"

create_sa() {
  local name=$1 desc=$2
  if ! exists gcloud iam service-accounts describe "${name}@${PROJECT_ID}.iam.gserviceaccount.com"; then
    gcloud iam service-accounts create "$name" --display-name="$desc"
  fi
}

grant_project() {
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$1" --role="$2" \
    --condition=None --quiet >/dev/null
  echo "  $1 -> $2"
}

say "Service accounts"
create_sa sa-web "Roastfolio web (public API)"
create_sa sa-worker "Roastfolio worker (pipeline)"
create_sa sa-tasks "Roastfolio Cloud Tasks invoker"
create_sa sa-build "Roastfolio Cloud Build"
sleep 5  # IAM is eventually consistent

say "Project roles"
grant_project "$SA_WEB" roles/datastore.user            # Firestore read/write
grant_project "$SA_WORKER" roles/datastore.user
grant_project "$SA_WORKER" roles/documentai.apiUser
grant_project "$SA_WORKER" roles/aiplatform.user         # Gemini + Nano Banana on Vertex
grant_project "$SA_BUILD" roles/run.developer            # deploy new revisions
grant_project "$SA_BUILD" roles/logging.logWriter        # build logs

say "actAs grants"
# web mints OIDC tokens as sa-tasks when it creates tasks.
gcloud iam service-accounts add-iam-policy-binding "$SA_TASKS" \
  --member="serviceAccount:$SA_WEB" --role=roles/iam.serviceAccountUser --quiet >/dev/null
# Cloud Build deploys revisions that run as sa-web / sa-worker.
for sa in "$SA_WEB" "$SA_WORKER"; do
  gcloud iam service-accounts add-iam-policy-binding "$sa" \
    --member="serviceAccount:$SA_BUILD" --role=roles/iam.serviceAccountUser --quiet >/dev/null
done
echo "  done"

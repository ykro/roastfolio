#!/usr/bin/env bash
# Cloud Build trigger: push to main -> tests -> images -> Cloud Run -> site bucket.
# Needs a one-time GitHub authorization in the browser (step 2 prints the link).
source "$(dirname "$0")/env.sh"
GITHUB_REPO="${GITHUB_REPO:-ykro/roastfolio}"
CONNECTION=rf-github
REPO_NAME=roastfolio
TRIGGER=roastfolio-main

say "1. sa-build can read sources uploaded by 'gcloud builds submit'"
SRC_BUCKET="gs://${PROJECT_ID}_cloudbuild"
exists gcloud storage buckets describe "$SRC_BUCKET" || gcloud storage buckets create "$SRC_BUCKET" --location=US
gcloud storage buckets add-iam-policy-binding "$SRC_BUCKET" \
  --member="serviceAccount:$SA_BUILD" --role=roles/storage.objectViewer >/dev/null
# The Cloud Build service agent stores the GitHub token in Secret Manager for the connection.
gcloud projects add-iam-policy-binding "$PROJECT_ID" --condition=None --quiet \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-cloudbuild.iam.gserviceaccount.com" \
  --role=roles/secretmanager.admin >/dev/null
echo "  done"

say "2. GitHub connection (2nd gen)"
if ! exists gcloud builds connections describe "$CONNECTION" --region="$REGION"; then
  gcloud builds connections create github "$CONNECTION" --region="$REGION"
fi
STAGE="$(gcloud builds connections describe "$CONNECTION" --region="$REGION" --format='value(installationState.stage)')"
if [[ "$STAGE" != "COMPLETE" ]]; then
  echo "  Open this link, authorize Cloud Build and install the app on $GITHUB_REPO, then run this script again:"
  gcloud builds connections describe "$CONNECTION" --region="$REGION" --format='value(installationState.actionUri)'
  exit 0
fi

say "3. Link repository"
exists gcloud builds repositories describe "$REPO_NAME" --connection="$CONNECTION" --region="$REGION" ||
  gcloud builds repositories create "$REPO_NAME" --connection="$CONNECTION" --region="$REGION" \
    --remote-uri="https://github.com/${GITHUB_REPO}.git"

say "4. Trigger on push to main"
REPO_ID="projects/${PROJECT_ID}/locations/${REGION}/connections/${CONNECTION}/repositories/${REPO_NAME}"
exists gcloud builds triggers describe "$TRIGGER" --region="$REGION" ||
  gcloud builds triggers create github --name="$TRIGGER" --region="$REGION" \
    --repository="$REPO_ID" --branch-pattern='^main$' --build-config=cloudbuild.yaml \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/${SA_BUILD}" \
    --description="Roastfolio: test, build, deploy on push to main"
echo "  Run it by hand: gcloud builds triggers run $TRIGGER --region=$REGION --branch=main"

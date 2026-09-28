#!/usr/bin/env bash
# Keyless alternative to 13-build-trigger.sh: a GitHub Actions workflow runs cloudbuild.yaml
# on every push to main, authenticated with Workload Identity Federation (no JSON keys).
# Only tokens minted by GitHub for ykro/roastfolio on refs/heads/main can impersonate sa-build.
source "$(dirname "$0")/env.sh"
GITHUB_REPO="${GITHUB_REPO:-ykro/roastfolio}"
POOL=github
PROVIDER=roastfolio

say "Workload Identity pool + GitHub OIDC provider"
exists gcloud iam workload-identity-pools describe "$POOL" --location=global ||
  gcloud iam workload-identity-pools create "$POOL" --location=global --display-name="GitHub Actions"
CONDITION="assertion.repository == '${GITHUB_REPO}' && assertion.ref == 'refs/heads/main'"
if exists gcloud iam workload-identity-pools providers describe "$PROVIDER" --location=global --workload-identity-pool="$POOL"; then
  gcloud iam workload-identity-pools providers update-oidc "$PROVIDER" --location=global \
    --workload-identity-pool="$POOL" --attribute-condition="$CONDITION" --quiet >/dev/null
else
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" --location=global \
    --workload-identity-pool="$POOL" --display-name="ykro/roastfolio (main)" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
    --attribute-condition="$CONDITION"
fi

say "The repo's workflow may act as sa-build"
POOL_ID="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}"
gcloud iam service-accounts add-iam-policy-binding "$SA_BUILD" --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/${POOL_ID}/attribute.repository/${GITHUB_REPO}" --quiet >/dev/null
# To start builds that run as itself, sa-build needs to create builds, upload the source
# tarball and "act as" its own identity.
gcloud projects add-iam-policy-binding "$PROJECT_ID" --condition=None --quiet \
  --member="serviceAccount:$SA_BUILD" --role=roles/cloudbuild.builds.editor >/dev/null
gcloud projects add-iam-policy-binding "$PROJECT_ID" --condition=None --quiet \
  --member="serviceAccount:$SA_BUILD" --role=roles/serviceusage.serviceUsageConsumer >/dev/null
gcloud storage buckets add-iam-policy-binding "gs://${PROJECT_ID}_cloudbuild" \
  --member="serviceAccount:$SA_BUILD" --role=roles/storage.objectAdmin >/dev/null
gcloud iam service-accounts add-iam-policy-binding "$SA_BUILD" --role=roles/iam.serviceAccountUser \
  --member="serviceAccount:$SA_BUILD" --quiet >/dev/null

echo "  provider: ${POOL_ID}/providers/${PROVIDER}"
echo "  service account: $SA_BUILD"

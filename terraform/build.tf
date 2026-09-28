# CI/CD: push to main -> Cloud Build trigger -> cloudbuild.yaml (tests, images, Cloud Run, site).
#
# The GitHub connection (2nd gen) needs a one-time browser authorization, so it takes two applies:
#   1. apply with github_app_installation_id / github_token_secret = null: creates the connection
#      (PENDING) and lets the Cloud Build service agent create the token secret.
#   2. open the `github_authorize_url` output, authorize the app and install it on the repo.
#   3. copy the installation id and token secret into terraform.tfvars and apply again:
#      repository + trigger are created and the agent's access shrinks to that one secret.

resource "google_cloudbuildv2_connection" "github" {
  name     = "rf-github"
  location = var.region

  github_config {
    app_installation_id = var.github_app_installation_id

    dynamic "authorizer_credential" {
      for_each = local.github_connected ? [1] : []
      content {
        oauth_token_secret_version = "projects/${var.project_id}/locations/${var.region}/secrets/${var.github_token_secret}/versions/latest"
      }
    }
  }

  depends_on = [google_project_service.apis]
}

# Step 1 only: the service agent must create the token secret during the browser authorization.
resource "google_project_iam_member" "cloudbuild_agent_secret_admin" {
  count = local.github_connected ? 0 : 1

  project = var.project_id
  role    = "roles/secretmanager.admin"
  member  = local.cloudbuild_agent
}

# Afterwards it only needs to read the token it stored (regional secret).
resource "google_secret_manager_regional_secret_iam_member" "cloudbuild_agent_token" {
  count = local.github_connected ? 1 : 0

  secret_id = var.github_token_secret
  location  = var.region
  role      = "roles/secretmanager.secretAccessor"
  member    = local.cloudbuild_agent
}

resource "google_cloudbuildv2_repository" "roastfolio" {
  count = local.github_connected ? 1 : 0

  name              = var.app
  location          = var.region
  parent_connection = google_cloudbuildv2_connection.github.name
  remote_uri        = "https://github.com/${var.github_repo}.git"
}

resource "google_cloudbuild_trigger" "main" {
  count = local.github_connected ? 1 : 0

  name            = "${var.app}-main"
  location        = var.region
  description     = "Roastfolio: test, build, deploy on push to main"
  filename        = "cloudbuild.yaml"
  service_account = google_service_account.sa["sa-build"].id

  repository_event_config {
    repository = google_cloudbuildv2_repository.roastfolio[0].id
    push {
      branch = "^main$"
    }
  }

  depends_on = [
    google_project_iam_member.sa,
    google_service_account_iam_member.build_actas,
    google_artifact_registry_repository_iam_member.build_writer,
    google_storage_bucket_iam_member.app,
    google_cloud_run_v2_service_iam_member.build_developer,
  ]
}

# `gcloud builds submit` by hand (see cloudbuild.yaml) uploads the source to the default
# <project>_cloudbuild bucket; sa-build must be able to read it. The bucket itself is shared
# with other builds in the project, so Terraform only manages this binding.
resource "google_storage_bucket_iam_member" "cloudbuild_source_build" {
  bucket = "${var.project_id}_cloudbuild"
  role   = "roles/storage.objectViewer"
  member = google_service_account.sa["sa-build"].member
}

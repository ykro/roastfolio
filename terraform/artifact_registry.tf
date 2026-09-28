resource "google_artifact_registry_repository" "images" {
  repository_id = var.app
  location      = var.region
  format        = "DOCKER"
  description   = "Roastfolio images"

  # Keep the 10 most recent versions, delete anything older than 30 days.
  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"

    most_recent_versions {
      keep_count = 10
    }
  }

  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"

    condition {
      older_than = "2592000s" # 30 days
      # gcloud stored TAG_STATE_UNSPECIFIED, which the provider rejects; ANY means the same.
      tag_state = "ANY"
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_artifact_registry_repository_iam_member" "build_writer" {
  repository = google_artifact_registry_repository.images.name
  location   = google_artifact_registry_repository.images.location
  role       = "roles/artifactregistry.writer"
  member     = google_service_account.sa["sa-build"].member
}

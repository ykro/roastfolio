locals {
  apis = toset([
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "firestore.googleapis.com",
    "storage.googleapis.com",
    "compute.googleapis.com",
    "cloudtasks.googleapis.com",
    "documentai.googleapis.com",
    "aiplatform.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ])
}

resource "google_project_service" "apis" {
  for_each = local.apis

  service = each.value

  # Other workloads share this project: never switch an API off on destroy.
  disable_on_destroy         = false
  disable_dependent_services = false
}

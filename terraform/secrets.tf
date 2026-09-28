# The only API key in the system (Apify). Terraform owns the secret "container" and who can
# read it, never the value: add it out of band so the token never lands in the state file.
#   printf '%s' 'apify_api_...' | gcloud secrets versions add apify-token --data-file=-
resource "google_secret_manager_secret" "apify" {
  secret_id = local.apify_secret

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_iam_member" "worker_apify" {
  secret_id = google_secret_manager_secret.apify.id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.sa["sa-worker"].member
}

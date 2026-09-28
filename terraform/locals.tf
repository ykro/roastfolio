locals {
  site_bucket    = "${var.project_id}-${var.app}-site"
  uploads_bucket = "${var.project_id}-${var.app}-uploads"
  cards_bucket   = "${var.project_id}-${var.app}-cards"

  web_service    = "${var.app}-web"
  worker_service = "${var.app}-worker"
  queue          = "roasts"
  apify_secret   = "apify-token"

  domain          = "${google_compute_global_address.lb.address}.nip.io"
  public_base_url = "https://${local.domain}"

  cloudbuild_agent = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"

  # The GitHub connection is usable once it has been authorized in the browser (see README).
  github_connected = var.github_app_installation_id != null && var.github_token_secret != null
}

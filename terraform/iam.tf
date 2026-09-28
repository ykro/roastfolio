# One service account per component. Project-level roles only where no finer scope exists;
# resource-level grants live next to the resource they protect (storage.tf, tasks.tf, ...).

locals {
  service_accounts = {
    sa-web    = "Roastfolio web (public API)"
    sa-worker = "Roastfolio worker (pipeline)"
    sa-tasks  = "Roastfolio Cloud Tasks invoker"
    sa-build  = "Roastfolio Cloud Build"
  }

  project_roles = {
    "web-datastore"     = { sa = "sa-web", role = "roles/datastore.user" }    # Firestore read/write
    "worker-datastore"  = { sa = "sa-worker", role = "roles/datastore.user" } # Firestore read/write
    "worker-documentai" = { sa = "sa-worker", role = "roles/documentai.apiUser" }
    "worker-aiplatform" = { sa = "sa-worker", role = "roles/aiplatform.user" }  # Gemini + Nano Banana
    "build-logwriter"   = { sa = "sa-build", role = "roles/logging.logWriter" } # build logs
  }
}

resource "google_service_account" "sa" {
  for_each = local.service_accounts

  account_id   = each.key
  display_name = each.value

  depends_on = [google_project_service.apis]
}

resource "google_project_iam_member" "sa" {
  for_each = local.project_roles

  project = var.project_id
  role    = each.value.role
  member  = google_service_account.sa[each.value.sa].member
}

# web mints OIDC tokens as sa-tasks when it creates tasks.
resource "google_service_account_iam_member" "web_actas_tasks" {
  service_account_id = google_service_account.sa["sa-tasks"].name
  role               = "roles/iam.serviceAccountUser"
  member             = google_service_account.sa["sa-web"].member
}

# Cloud Build deploys revisions that run as sa-web / sa-worker.
resource "google_service_account_iam_member" "build_actas" {
  for_each = toset(["sa-web", "sa-worker"])

  service_account_id = google_service_account.sa[each.key].name
  role               = "roles/iam.serviceAccountUser"
  member             = google_service_account.sa["sa-build"].member
}

# site    public, served by the LB with Cloud CDN; Cloud Build publishes the frontend.
# uploads private PDFs, deleted after 1 day.
# cards   public certificates (CDN), deleted after 1 day.

resource "google_storage_bucket" "site" {
  name                        = local.site_bucket
  location                    = var.region
  uniform_bucket_level_access = true

  depends_on = [google_project_service.apis]
}

resource "google_storage_bucket" "uploads" {
  name                        = local.uploads_bucket
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 1
    }
  }

  # No soft delete: a CV promised gone in 24 h must not stay restorable for 7 more days.
  soft_delete_policy {
    retention_duration_seconds = 0
  }

  depends_on = [google_project_service.apis]
}

resource "google_storage_bucket" "cards" {
  name                        = local.cards_bucket
  location                    = var.region
  uniform_bucket_level_access = true

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 1
    }
  }

  # No soft delete: a CV promised gone in 24 h must not stay restorable for 7 more days.
  soft_delete_policy {
    retention_duration_seconds = 0
  }

  depends_on = [google_project_service.apis]
}

# Who can do what on each bucket.
locals {
  bucket_iam = {
    # site: public read (backend bucket), Cloud Build publishes the frontend.
    # legacyObjectReader = get by name only; objectViewer would also let anyone list the bucket.
    site_public = { bucket = local.site_bucket, role = "roles/storage.legacyObjectReader", member = "allUsers" }
    site_build  = { bucket = local.site_bucket, role = "roles/storage.objectAdmin", member = "sa-build" }
    # uploads: web writes, worker reads
    uploads_web    = { bucket = local.uploads_bucket, role = "roles/storage.objectCreator", member = "sa-web" }
    uploads_worker = { bucket = local.uploads_bucket, role = "roles/storage.objectViewer", member = "sa-worker" }
    # cards: public read; objectUser (not objectCreator) so a retried task can overwrite a half-written card
    cards_public = { bucket = local.cards_bucket, role = "roles/storage.legacyObjectReader", member = "allUsers" }
    cards_worker = { bucket = local.cards_bucket, role = "roles/storage.objectUser", member = "sa-worker" }
  }
}

resource "google_storage_bucket_iam_member" "app" {
  for_each = local.bucket_iam

  bucket = each.value.bucket
  role   = each.value.role
  member = each.value.member == "allUsers" ? "allUsers" : google_service_account.sa[each.value.member].member

  depends_on = [google_storage_bucket.site, google_storage_bucket.uploads, google_storage_bucket.cards]
}

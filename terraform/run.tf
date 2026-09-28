# Terraform owns the runtime configuration (env, service account, ingress, limits).
# Cloud Build only swaps the image on every push to main, so the image is ignored here.

# --- Worker: private, internal ingress, invoked only by Cloud Tasks ------------------------
# Cloud Tasks traffic counts as internal, so nothing on the internet can even reach the URL.
resource "google_cloud_run_v2_service" "worker" {
  name     = local.worker_service
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  template {
    service_account                  = google_service_account.sa["sa-worker"].email
    timeout                          = "600s"
    max_instance_request_concurrency = 4

    scaling {
      max_instance_count = 5
    }

    containers {
      image = var.initial_image

      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      ports {
        name           = "http1"
        container_port = 8080
      }

      dynamic "env" {
        for_each = {
          PROJECT_ID         = var.project_id
          FIRESTORE_DB       = google_firestore_database.roastfolio.name
          UPLOADS_BUCKET     = google_storage_bucket.uploads.name
          CARDS_BUCKET       = google_storage_bucket.cards.name
          DOCAI_LOCATION     = var.docai_location
          DOCAI_PROCESSOR_ID = local.docai_processor_id
          GENAI_LOCATION     = var.genai_location
          GEMINI_TEXT_MODEL  = var.gemini_text_model
          GEMINI_IMAGE_MODEL = var.gemini_image_model
          APIFY_TOKEN_SECRET = google_secret_manager_secret.apify.secret_id
          MAX_ATTEMPTS       = "4"
        }
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }

  depends_on = [google_project_service.apis]
}

resource "google_cloud_run_v2_service_iam_member" "worker_invoker" {
  name     = google_cloud_run_v2_service.worker.name
  location = google_cloud_run_v2_service.worker.location
  role     = "roles/run.invoker"
  member   = google_service_account.sa["sa-tasks"].member
}

# --- Web: reachable only through the Load Balancer ----------------------------------------
# INTERNAL_LOAD_BALANCER blocks the *.run.app URL from the internet; with the invoker IAM
# check disabled, anonymous users get in once they come through the LB.
resource "google_cloud_run_v2_service" "web" {
  name                 = local.web_service
  location             = var.region
  ingress              = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  invoker_iam_disabled = true

  template {
    service_account                  = google_service_account.sa["sa-web"].email
    timeout                          = "60s"
    max_instance_request_concurrency = 40

    scaling {
      max_instance_count = 5
    }

    containers {
      image = var.initial_image

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      ports {
        name           = "http1"
        container_port = 8080
      }

      dynamic "env" {
        for_each = {
          PROJECT_ID      = var.project_id
          FIRESTORE_DB    = google_firestore_database.roastfolio.name
          UPLOADS_BUCKET  = google_storage_bucket.uploads.name
          SITE_BUCKET     = google_storage_bucket.site.name
          TASKS_LOCATION  = google_cloud_tasks_queue.roasts.location
          TASKS_QUEUE     = google_cloud_tasks_queue.roasts.name
          WORKER_URL      = google_cloud_run_v2_service.worker.uri
          TASKS_SA_EMAIL  = google_service_account.sa["sa-tasks"].email
          PUBLIC_BASE_URL = local.public_base_url # for og:image in /r/{id}
        }
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }

  depends_on = [google_project_service.apis]
}

# sa-build may deploy new revisions of these two services only (no project-wide run.developer).
resource "google_cloud_run_v2_service_iam_member" "build_developer" {
  for_each = {
    web    = google_cloud_run_v2_service.web.name
    worker = google_cloud_run_v2_service.worker.name
  }

  name     = each.value
  location = var.region
  role     = "roles/run.developer"
  member   = google_service_account.sa["sa-build"].member
}

# Bounded concurrency protects Vertex quotas; 4 attempts = 1 + 3 retries.
resource "google_cloud_tasks_queue" "roasts" {
  name     = local.queue
  location = var.region

  rate_limits {
    max_concurrent_dispatches = 5
    max_dispatches_per_second = 2
  }

  retry_config {
    max_attempts  = 4
    min_backoff   = "10s"
    max_backoff   = "120s"
    max_doublings = 3
  }

  depends_on = [google_project_service.apis]
}

resource "google_cloud_tasks_queue_iam_member" "web_enqueuer" {
  name     = google_cloud_tasks_queue.roasts.name
  location = google_cloud_tasks_queue.roasts.location
  role     = "roles/cloudtasks.enqueuer"
  member   = google_service_account.sa["sa-web"].member
}

output "public_url" {
  description = "Public entry point (LB + managed certificate)."
  value       = local.public_base_url
}

output "lb_ip" {
  description = "Global static IP of the load balancer."
  value       = google_compute_global_address.lb.address
}

output "web_service_uri" {
  description = "Cloud Run web URL (returns 404 from the internet: ingress is LB-only)."
  value       = google_cloud_run_v2_service.web.uri
}

output "worker_url" {
  description = "Cloud Run worker URL (internal only, invoked by Cloud Tasks)."
  value       = google_cloud_run_v2_service.worker.uri
}

output "docai_processor_id" {
  description = "Document AI Layout Parser processor id."
  value       = local.docai_processor_id
}

output "artifact_registry" {
  description = "Docker registry path for the web and worker images."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}

output "dashboard_url" {
  description = "Cloud Monitoring dashboard."
  value       = "https://console.cloud.google.com/monitoring/dashboards/builder/${element(split("/", google_monitoring_dashboard.roastfolio.id), 3)}?project=${var.project_id}"
}

output "github_connection_stage" {
  description = "Installation stage of the GitHub connection (COMPLETE once authorized)."
  value       = one(google_cloudbuildv2_connection.github.installation_state[*].stage)
}

output "github_authorize_url" {
  description = "Open this link to authorize Cloud Build on GitHub (only while the connection is pending)."
  value       = one(google_cloudbuildv2_connection.github.installation_state[*].action_uri)
}

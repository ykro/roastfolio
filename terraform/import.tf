# Adopts the resources that infra/NN-*.sh already created, so the first apply imports them
# instead of trying to create duplicates. Run `terraform plan` and check it says "to import"
# (plus in-place updates, if any) and nothing "to destroy" before applying.
#
# Starting from an empty project? Delete this file: several blocks point at live ids
# (Document AI processor, notification channel, alert policy, dashboard, trigger).
# Once the first apply succeeds the blocks are no-ops and can be deleted too.

locals {
  imp_p   = var.project_id
  imp_loc = "projects/${var.project_id}/locations/${var.region}"
  imp_sa  = { for k in keys(local.service_accounts) : k => "${k}@${var.project_id}.iam.gserviceaccount.com" }
}

# --- APIs + IAM -----------------------------------------------------------------------------

import {
  for_each = local.apis
  to       = google_project_service.apis[each.key]
  id       = "${local.imp_p}/${each.key}"
}

import {
  for_each = local.service_accounts
  to       = google_service_account.sa[each.key]
  id       = "projects/${local.imp_p}/serviceAccounts/${local.imp_sa[each.key]}"
}

import {
  for_each = local.project_roles
  to       = google_project_iam_member.sa[each.key]
  id       = "${local.imp_p} ${each.value.role} serviceAccount:${local.imp_sa[each.value.sa]}"
}

import {
  to = google_service_account_iam_member.web_actas_tasks
  id = "projects/${local.imp_p}/serviceAccounts/${local.imp_sa["sa-tasks"]} roles/iam.serviceAccountUser serviceAccount:${local.imp_sa["sa-web"]}"
}

import {
  for_each = toset(["sa-web", "sa-worker"])
  to       = google_service_account_iam_member.build_actas[each.key]
  id       = "projects/${local.imp_p}/serviceAccounts/${local.imp_sa[each.key]} roles/iam.serviceAccountUser serviceAccount:${local.imp_sa["sa-build"]}"
}

# --- Storage --------------------------------------------------------------------------------

import {
  to = google_storage_bucket.site
  id = local.site_bucket
}

import {
  to = google_storage_bucket.uploads
  id = local.uploads_bucket
}

import {
  to = google_storage_bucket.cards
  id = local.cards_bucket
}

import {
  for_each = local.bucket_iam
  to       = google_storage_bucket_iam_member.app[each.key]
  id       = "${each.value.bucket} ${each.value.role} ${each.value.member == "allUsers" ? "allUsers" : "serviceAccount:${local.imp_sa[each.value.member]}"}"
}

# --- Firestore, Document AI, Tasks, Secret Manager, Artifact Registry -----------------------

import {
  to = google_firestore_database.roastfolio
  id = "projects/${local.imp_p}/databases/${var.app}"
}

import {
  to = google_firestore_field.roasts_ttl
  id = "projects/${local.imp_p}/databases/${var.app}/collectionGroups/roasts/fields/expiresAt"
}

import {
  to = google_document_ai_processor.layout
  id = "projects/${local.imp_p}/locations/${var.docai_location}/processors/aed820252702ea66"
}

import {
  to = google_cloud_tasks_queue.roasts
  id = "${local.imp_loc}/queues/${local.queue}"
}

import {
  to = google_cloud_tasks_queue_iam_member.web_enqueuer
  id = "${local.imp_loc}/queues/${local.queue} roles/cloudtasks.enqueuer serviceAccount:${local.imp_sa["sa-web"]}"
}

import {
  to = google_secret_manager_secret.apify
  id = "projects/${local.imp_p}/secrets/${local.apify_secret}"
}

import {
  to = google_secret_manager_secret_iam_member.worker_apify
  id = "projects/${local.imp_p}/secrets/${local.apify_secret} roles/secretmanager.secretAccessor serviceAccount:${local.imp_sa["sa-worker"]}"
}

import {
  to = google_artifact_registry_repository.images
  id = "${local.imp_loc}/repositories/${var.app}"
}

import {
  to = google_artifact_registry_repository_iam_member.build_writer
  id = "${local.imp_loc}/repositories/${var.app} roles/artifactregistry.writer serviceAccount:${local.imp_sa["sa-build"]}"
}

# --- Cloud Run ------------------------------------------------------------------------------

import {
  to = google_cloud_run_v2_service.web
  id = "${local.imp_loc}/services/${local.web_service}"
}

import {
  to = google_cloud_run_v2_service.worker
  id = "${local.imp_loc}/services/${local.worker_service}"
}

import {
  to = google_cloud_run_v2_service_iam_member.worker_invoker
  id = "${local.imp_loc}/services/${local.worker_service} roles/run.invoker serviceAccount:${local.imp_sa["sa-tasks"]}"
}

import {
  for_each = { web = local.web_service, worker = local.worker_service }
  to       = google_cloud_run_v2_service_iam_member.build_developer[each.key]
  id       = "${local.imp_loc}/services/${each.value} roles/run.developer serviceAccount:${local.imp_sa["sa-build"]}"
}

# --- Load balancer + Cloud Armor ------------------------------------------------------------

import {
  to = google_compute_global_address.lb
  id = "projects/${local.imp_p}/global/addresses/rf-ip"
}

import {
  to = google_compute_region_network_endpoint_group.web
  id = "projects/${local.imp_p}/regions/${var.region}/networkEndpointGroups/rf-web-neg"
}

import {
  to = google_compute_backend_service.web
  id = "projects/${local.imp_p}/global/backendServices/rf-web-backend"
}

import {
  to = google_compute_backend_bucket.site
  id = "projects/${local.imp_p}/global/backendBuckets/rf-site-backend"
}

import {
  to = google_compute_backend_bucket.cards
  id = "projects/${local.imp_p}/global/backendBuckets/rf-cards-backend"
}

import {
  to = google_compute_url_map.https
  id = "projects/${local.imp_p}/global/urlMaps/rf-url-map"
}

import {
  to = google_compute_managed_ssl_certificate.lb
  id = "projects/${local.imp_p}/global/sslCertificates/rf-cert"
}

import {
  to = google_compute_target_https_proxy.lb
  id = "projects/${local.imp_p}/global/targetHttpsProxies/rf-https-proxy"
}

import {
  to = google_compute_global_forwarding_rule.https
  id = "projects/${local.imp_p}/global/forwardingRules/rf-https-rule"
}

import {
  to = google_compute_url_map.http_redirect
  id = "projects/${local.imp_p}/global/urlMaps/rf-http-redirect"
}

import {
  to = google_compute_target_http_proxy.lb
  id = "projects/${local.imp_p}/global/targetHttpProxies/rf-http-proxy"
}

import {
  to = google_compute_global_forwarding_rule.http
  id = "projects/${local.imp_p}/global/forwardingRules/rf-http-rule"
}

import {
  to = google_compute_security_policy.armor
  id = "projects/${local.imp_p}/global/securityPolicies/rf-armor"
}

# --- Observability --------------------------------------------------------------------------

import {
  for_each = local.counters
  to       = google_logging_metric.counter[each.key]
  id       = each.key
}

import {
  to = google_logging_metric.step_duration
  id = "roastfolio_step_duration"
}

import {
  to = google_monitoring_notification_channel.email
  id = "projects/${local.imp_p}/notificationChannels/8929275583903350266"
}

import {
  to = google_monitoring_alert_policy.error_rate
  id = "projects/${local.imp_p}/alertPolicies/827651393391518385"
}

import {
  to = google_monitoring_dashboard.roastfolio
  id = "projects/${local.imp_p}/dashboards/b575afa8-6f52-4d2e-aed0-b426b13f333d"
}

# --- Cloud Build ----------------------------------------------------------------------------

import {
  to = google_cloudbuildv2_connection.github
  id = "${local.imp_loc}/connections/rf-github"
}

import {
  for_each = local.github_connected ? toset(["this"]) : toset([])
  to       = google_secret_manager_regional_secret_iam_member.cloudbuild_agent_token[0]
  id       = "${local.imp_loc}/secrets/${var.github_token_secret} roles/secretmanager.secretAccessor ${local.cloudbuild_agent}"
}

import {
  for_each = local.github_connected ? toset(["this"]) : toset([])
  to       = google_cloudbuildv2_repository.roastfolio[0]
  id       = "${local.imp_loc}/connections/rf-github/repositories/${var.app}"
}

import {
  for_each = local.github_connected ? toset(["this"]) : toset([])
  to       = google_cloudbuild_trigger.main[0]
  id       = "${local.imp_loc}/triggers/f9c54bae-1c40-4d02-99bf-4224c6828dea"
}

import {
  to = google_storage_bucket_iam_member.cloudbuild_source_build
  id = "${local.imp_p}_cloudbuild roles/storage.objectViewer serviceAccount:${local.imp_sa["sa-build"]}"
}

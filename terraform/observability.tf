# Log-based metrics built from the JSON logs (field `event`), an error-rate alert and a dashboard.
# Keep the event names in sync with web/ and worker/ (roast_queued, roast_done, roast_failed,
# step_finished).

locals {
  run_logs = "resource.type=\"cloud_run_revision\""

  counters = {
    roastfolio_roasts_queued = {
      description = "Roasts created (web)"
      service     = local.web_service
      event       = "roast_queued"
    }
    roastfolio_roasts_done = {
      description = "Roasts finished OK (worker)"
      service     = local.worker_service
      event       = "roast_done"
    }
    roastfolio_roasts_failed = {
      description = "Roasts marked failed (worker)"
      service     = local.worker_service
      event       = "roast_failed"
    }
    roastfolio_cards_generic = {
      description = "Roasts that got the generic certificate because Nano Banana failed (worker)"
      service     = local.worker_service
      event       = "card_fallback"
    }
  }
}

resource "google_logging_metric" "counter" {
  for_each = local.counters

  name        = each.key
  description = each.value.description
  filter      = "${local.run_logs} AND resource.labels.service_name=\"${each.value.service}\" AND jsonPayload.event=\"${each.value.event}\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_logging_metric" "step_duration" {
  name            = "roastfolio_step_duration"
  description     = "Duration of each pipeline step (extracting, roasting, rendering)"
  filter          = "${local.run_logs} AND resource.labels.service_name=\"${local.worker_service}\" AND jsonPayload.event=\"step_finished\""
  value_extractor = "EXTRACT(jsonPayload.durationMs)"

  label_extractors = {
    step = "EXTRACT(jsonPayload.step)"
  }

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "DISTRIBUTION"
    unit        = "ms"

    labels {
      key         = "step"
      value_type  = "STRING"
      description = "Pipeline step"
    }
  }

  bucket_options {
    exponential_buckets {
      num_finite_buckets = 24
      growth_factor      = 1.5
      scale              = 100
    }
  }
}

# --- Alert ----------------------------------------------------------------------------------

resource "google_monitoring_notification_channel" "email" {
  display_name = "Roastfolio alerts"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }
}

locals {
  # PromQL names of the user-defined log-based metrics.
  prom_done   = "logging_googleapis_com:user_${google_logging_metric.counter["roastfolio_roasts_done"].name}"
  prom_failed = "logging_googleapis_com:user_${google_logging_metric.counter["roastfolio_roasts_failed"].name}"

  failed_15m = "(sum(increase(${local.prom_failed}[15m])) or vector(0))"
  total_15m  = "(${local.failed_15m} + (sum(increase(${local.prom_done}[15m])) or vector(0)))"
}

# Error rate > 10% in 15 min, only with >= 5 roasts (one failure at 3 a.m. doesn't page).
resource "google_monitoring_alert_policy" "error_rate" {
  display_name          = "Roastfolio: tasa de error > 10% (15 min)"
  combiner              = "OR"
  notification_channels = [google_monitoring_notification_channel.email.id]

  conditions {
    display_name = "failed / (done + failed) > 10%"

    condition_prometheus_query_language {
      query               = "(${local.failed_15m} / ${local.total_15m} > 0.1) and on() (${local.total_15m} >= 5)"
      duration            = "0s"
      evaluation_interval = "60s"
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    mime_type = "text/markdown"
    content   = "Más del 10% de los roasts fallaron en 15 minutos.\n\nRevisa los logs: `resource.labels.service_name=\"${local.worker_service}\" jsonPayload.event=\"roast_failed\"`"
  }
}

# --- Dashboard ------------------------------------------------------------------------------
# Same six charts as infra/12-observability.sh, written as HCL and serialized with jsonencode.

locals {
  # LB request counter for this URL map; the closing brace is added per query.
  lb_requests = "loadbalancing_googleapis_com:https_request_count{monitored_resource=\"https_lb_rule\",url_map_name=\"${google_compute_url_map.https.name}\""

  dashboard_charts = [
    {
      title = "Roasts por hora", x = 0, y = 0, plot = "STACKED_BAR"
      series = [
        { legend = "done", query = "sum(increase(${local.prom_done}[1h]))" },
        { legend = "failed", query = "sum(increase(${local.prom_failed}[1h]))" },
      ]
    },
    {
      title = "Latencia por paso, p95 (ms)", x = 6, y = 0, plot = "LINE"
      series = [{
        legend = "$${labels.step}"
        query  = "histogram_quantile(0.95, sum by (step, le) (rate(logging_googleapis_com:user_${google_logging_metric.step_duration.name}_bucket[30m])))"
      }]
    },
    {
      title = "CDN: cache hit ratio (site + cards)", x = 0, y = 4, plot = "LINE"
      series = [{
        legend = "hit ratio"
        query  = "sum(rate(${local.lb_requests},cache_result=\"HIT\"}[10m])) / sum(rate(${local.lb_requests},cache_result!=\"DISABLED\"}[10m]))"
      }]
    },
    {
      title = "Peticiones por resultado de caché", x = 6, y = 4, plot = "STACKED_AREA"
      series = [{
        legend = "$${labels.cache_result}"
        query  = "sum by (cache_result) (rate(${local.lb_requests}}[5m]))"
      }]
    },
    {
      title = "Respuestas del LB por código", x = 0, y = 8, plot = "LINE"
      series = [{
        legend = "$${labels.response_code_class}"
        query  = "sum by (response_code_class) (rate(${local.lb_requests}}[5m]))"
      }]
    },
    {
      title = "Cloud Tasks: tareas en cola", x = 6, y = 8, plot = "LINE"
      series = [{
        legend = "depth"
        query  = "sum(cloudtasks_googleapis_com:queue_depth{queue_id=\"${google_cloud_tasks_queue.roasts.name}\"})"
      }]
    },
  ]
}

resource "google_monitoring_dashboard" "roastfolio" {
  dashboard_json = jsonencode({
    displayName = "Roastfolio"
    mosaicLayout = {
      columns = 12
      tiles = [for c in local.dashboard_charts : merge(
        { width = 6, height = 4 },
        # The API drops zero coordinates; omit them so the plan stays clean.
        { for k, v in { xPos = c.x, yPos = c.y } : k => v if v > 0 },
        {
          widget = {
            title = c.title
            xyChart = {
              dataSets = [for s in c.series : {
                timeSeriesQuery = { prometheusQuery = s.query }
                plotType        = c.plot
                legendTemplate  = s.legend
                targetAxis      = "Y1"
              }]
            }
          }
        },
      )]
    }
  })
}

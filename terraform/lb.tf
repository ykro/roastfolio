# Global external Application Load Balancer:
#   /api/*, /r/*    -> Cloud Run web (serverless NEG)
#   /cards/*        -> cards bucket (CDN, max 1 h)
#   everything else -> site bucket (CDN, honors Cache-Control from the upload)
# HTTPS with a Google-managed certificate for <IP>.nip.io, plus an HTTP -> HTTPS redirect.

resource "google_compute_global_address" "lb" {
  name       = "rf-ip"
  ip_version = "IPV4"

  depends_on = [google_project_service.apis]
}

# --- Backends -------------------------------------------------------------------------------

resource "google_compute_region_network_endpoint_group" "web" {
  name                  = "rf-web-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.web.name
  }
}

resource "google_compute_backend_service" "web" {
  name                            = "rf-web-backend"
  load_balancing_scheme           = "EXTERNAL_MANAGED"
  protocol                        = "HTTP"
  connection_draining_timeout_sec = 0
  security_policy                 = google_compute_security_policy.armor.id

  backend {
    group = google_compute_region_network_endpoint_group.web.id
  }

  log_config {
    enable      = true
    sample_rate = 1
  }
}

resource "google_compute_backend_bucket" "site" {
  name        = "rf-site-backend"
  bucket_name = google_storage_bucket.site.name
  enable_cdn  = true

  cdn_policy {
    cache_mode         = "USE_ORIGIN_HEADERS"
    negative_caching   = true
    request_coalescing = true
    serve_while_stale  = 86400
  }
}

# Cards: cache up to 1 h so a deleted card is never served for long.
resource "google_compute_backend_bucket" "cards" {
  name        = "rf-cards-backend"
  bucket_name = google_storage_bucket.cards.name
  enable_cdn  = true

  cdn_policy {
    cache_mode         = "CACHE_ALL_STATIC"
    default_ttl        = 3600
    max_ttl            = 3600
    client_ttl         = 3600
    negative_caching   = true
    request_coalescing = true
    serve_while_stale  = 86400
  }
}

# --- Routing --------------------------------------------------------------------------------

resource "google_compute_url_map" "https" {
  name            = "rf-url-map"
  default_service = google_compute_backend_bucket.site.id

  host_rule {
    hosts        = ["*"]
    path_matcher = "roastfolio"
  }

  path_matcher {
    name            = "roastfolio"
    default_service = google_compute_backend_bucket.site.id

    route_rules {
      priority = 1
      service  = google_compute_backend_service.web.id
      match_rules {
        prefix_match = "/api/"
      }
    }

    route_rules {
      priority = 2
      service  = google_compute_backend_service.web.id
      match_rules {
        prefix_match = "/r/"
      }
    }

    # /cards/abc.jpg -> object abc.jpg in the cards bucket
    route_rules {
      priority = 3
      service  = google_compute_backend_bucket.cards.id
      match_rules {
        prefix_match = "/cards/"
      }
      route_action {
        url_rewrite {
          path_prefix_rewrite = "/"
        }
      }
    }

    # The SPA entry point
    route_rules {
      priority = 4
      service  = google_compute_backend_bucket.site.id
      match_rules {
        full_path_match = "/"
      }
      route_action {
        url_rewrite {
          path_prefix_rewrite = "/index.html"
        }
      }
    }
  }
}

# --- HTTPS :443 -----------------------------------------------------------------------------

# Provisioning takes 15-60 min after the forwarding rule exists.
resource "google_compute_managed_ssl_certificate" "lb" {
  name = "rf-cert"

  managed {
    domains = [local.domain]
  }
}

resource "google_compute_target_https_proxy" "lb" {
  name             = "rf-https-proxy"
  url_map          = google_compute_url_map.https.id
  ssl_certificates = [google_compute_managed_ssl_certificate.lb.id]
}

resource "google_compute_global_forwarding_rule" "https" {
  name                  = "rf-https-rule"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.lb.address
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_target_https_proxy.lb.id
}

# --- HTTP :80 -> HTTPS redirect -------------------------------------------------------------

resource "google_compute_url_map" "http_redirect" {
  name = "rf-http-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "lb" {
  name    = "rf-http-proxy"
  url_map = google_compute_url_map.http_redirect.id
}

resource "google_compute_global_forwarding_rule" "http" {
  name                  = "rf-http-rule"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.lb.address
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.lb.id
}

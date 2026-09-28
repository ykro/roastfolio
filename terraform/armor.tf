# Cloud Armor on the web backend service.
# The first matching rule wins, and a throttle rule "allows" conforming traffic,
# so the OWASP deny rules (1000-1070) must run before the rate limits (2000+).

locals {
  owasp_rules = [
    "sqli-v33-stable",
    "xss-v33-stable",
    "lfi-v33-stable",
    "rfi-v33-stable",
    "rce-v33-stable",
    "methodenforcement-v33-stable",
    "scannerdetection-v33-stable",
    "protocolattack-v33-stable",
  ]

  # The PDF upload is binary: body inspection would flag random bytes as SQLi/XSS.
  # WAF skips that one endpoint; the app's strict validation + the rate limit protect it.
  skip_upload = "!(request.method == 'POST' && request.path == '/api/roasts')"
}

resource "google_compute_security_policy" "armor" {
  name        = "rf-armor"
  description = "Roastfolio: OWASP + rate limits"
  type        = "CLOUD_ARMOR"

  # OWASP preconfigured rules, sensitivity 1 = fewest false positives.
  dynamic "rule" {
    for_each = local.owasp_rules
    content {
      priority    = 1000 + rule.key * 10
      action      = "deny(403)"
      description = "OWASP ${rule.value}"
      match {
        expr {
          expression = "${local.skip_upload} && evaluatePreconfiguredWaf('${rule.value}', {'sensitivity': 1})"
        }
      }
    }
  }

  # 5 roasts per IP every 10 minutes: each one costs Document AI + Gemini + Nano Banana.
  rule {
    priority    = 2000
    action      = "throttle"
    description = "5 POST /api/roasts per IP / 10 min"
    match {
      expr {
        expression = "request.method == 'POST' && request.path == '/api/roasts'"
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = 5
        interval_sec = 600
      }
    }
  }

  # Everything else (status polling every 2 s = 30/min, share pages): generous ceiling.
  rule {
    priority    = 2100
    action      = "throttle"
    description = "300 req per IP / min"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = 300
        interval_sec = 60
      }
    }
  }

  rule {
    priority    = 2147483647
    action      = "allow"
    description = "default rule"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }

  depends_on = [google_project_service.apis]
}

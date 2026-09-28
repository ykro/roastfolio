#!/usr/bin/env bash
# Cloud Armor on the web backend service.
# Rule order matters: the first match wins, and a throttle rule "allows" conforming traffic,
# so the OWASP rules (deny) must run before the rate limits.
source "$(dirname "$0")/env.sh"
POLICY="$ARMOR_POLICY"

say "Security policy '$POLICY'"
exists gcloud compute security-policies describe "$POLICY" ||
  gcloud compute security-policies create "$POLICY" --description="Roastfolio: OWASP + rate limits"

upsert_rule() {
  local prio=$1; shift
  if exists gcloud compute security-policies rules describe "$prio" --security-policy="$POLICY"; then
    gcloud compute security-policies rules update "$prio" --security-policy="$POLICY" "$@" --quiet >/dev/null
  else
    gcloud compute security-policies rules create "$prio" --security-policy="$POLICY" "$@" --quiet >/dev/null
  fi
  echo "  rule $prio ok"
}

say "OWASP preconfigured rules (sensitivity 1 = fewest false positives)"
# The PDF upload is binary: body inspection would flag random bytes as SQLi/XSS.
# We skip WAF for that one endpoint and rely on the app's strict validation + the rate limit.
SKIP_UPLOAD="!(request.method == 'POST' && request.path == '/api/roasts')"
prio=1000
for rule in sqli-v33-stable xss-v33-stable lfi-v33-stable rfi-v33-stable rce-v33-stable \
            methodenforcement-v33-stable scannerdetection-v33-stable protocolattack-v33-stable; do
  upsert_rule $prio --action=deny-403 \
    --expression="${SKIP_UPLOAD} && evaluatePreconfiguredWaf('${rule}', {'sensitivity': 1})" \
    --description="OWASP ${rule}"
  prio=$((prio + 10))
done

say "Rate limits"
# 5 roasts per IP every 10 minutes: each one costs Document AI + Gemini + Nano Banana.
upsert_rule 2000 --action=throttle \
  --expression="request.method == 'POST' && request.path == '/api/roasts'" \
  --rate-limit-threshold-count=5 --rate-limit-threshold-interval-sec=600 \
  --conform-action=allow --exceed-action=deny-429 --enforce-on-key=IP \
  --description="5 POST /api/roasts per IP / 10 min"
# Everything else (status polling every 2 s = 30/min, share pages): generous ceiling.
upsert_rule 2100 --action=throttle --src-ip-ranges='*' \
  --rate-limit-threshold-count=300 --rate-limit-threshold-interval-sec=60 \
  --conform-action=allow --exceed-action=deny-429 --enforce-on-key=IP \
  --description="300 req per IP / min"

say "Attach to $LB_WEB_BACKEND"
gcloud compute backend-services update "$LB_WEB_BACKEND" --global --security-policy="$POLICY" --quiet >/dev/null
echo "  done"

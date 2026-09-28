#!/usr/bin/env bash
# Global external Application Load Balancer:
#   /api/*, /r/*  -> Cloud Run web (serverless NEG)
#   /cards/*      -> cards bucket (CDN, max 1 h)
#   everything else -> site bucket (CDN, honors Cache-Control from the upload)
# HTTPS with a Google-managed certificate for <IP>.nip.io, plus an HTTP -> HTTPS redirect.
source "$(dirname "$0")/env.sh"
G=(--global)

say "Static IP"
exists gcloud compute addresses describe "$LB_IP_NAME" "${G[@]}" ||
  gcloud compute addresses create "$LB_IP_NAME" "${G[@]}" --ip-version=IPV4
IP="$(gcloud compute addresses describe "$LB_IP_NAME" "${G[@]}" --format='value(address)')"
DOMAIN="${IP}.nip.io"
echo "https://${DOMAIN}" > "$GEN_DIR/public-base-url"
echo "  $IP -> $DOMAIN"

say "Serverless NEG + backend service for web"
exists gcloud compute network-endpoint-groups describe "$LB_NEG" --region="$REGION" ||
  gcloud compute network-endpoint-groups create "$LB_NEG" --region="$REGION" \
    --network-endpoint-type=serverless --cloud-run-service="$WEB_SERVICE"
exists gcloud compute backend-services describe "$LB_WEB_BACKEND" "${G[@]}" ||
  gcloud compute backend-services create "$LB_WEB_BACKEND" "${G[@]}" \
    --load-balancing-scheme=EXTERNAL_MANAGED --enable-logging --logging-sample-rate=1
if [[ -z "$(gcloud compute backend-services describe "$LB_WEB_BACKEND" "${G[@]}" --format='value(backends)')" ]]; then
  gcloud compute backend-services add-backend "$LB_WEB_BACKEND" "${G[@]}" \
    --network-endpoint-group="$LB_NEG" --network-endpoint-group-region="$REGION"
fi

say "Backend buckets with Cloud CDN"
exists gcloud compute backend-buckets describe "$LB_SITE_BACKEND" ||
  gcloud compute backend-buckets create "$LB_SITE_BACKEND" --gcs-bucket-name="$SITE_BUCKET" \
    --enable-cdn --cache-mode=USE_ORIGIN_HEADERS
# Cards: cache up to 1 h so a deleted card is never served for long.
exists gcloud compute backend-buckets describe "$LB_CARDS_BACKEND" ||
  gcloud compute backend-buckets create "$LB_CARDS_BACKEND" --gcs-bucket-name="$CARDS_BUCKET" \
    --enable-cdn --cache-mode=CACHE_ALL_STATIC --default-ttl=3600 --max-ttl=3600 --client-ttl=3600

say "URL map (path routing)"
P="https://www.googleapis.com/compute/v1/projects/${PROJECT_ID}/global"
cat > "$GEN_DIR/url-map.yaml" <<YAML
name: ${LB_URL_MAP}
defaultService: ${P}/backendBuckets/${LB_SITE_BACKEND}
hostRules:
- hosts: ['*']
  pathMatcher: roastfolio
pathMatchers:
- name: roastfolio
  defaultService: ${P}/backendBuckets/${LB_SITE_BACKEND}
  routeRules:
  - priority: 1
    matchRules: [{prefixMatch: /api/}]
    service: ${P}/backendServices/${LB_WEB_BACKEND}
  - priority: 2
    matchRules: [{prefixMatch: /r/}]
    service: ${P}/backendServices/${LB_WEB_BACKEND}
  - priority: 3
    # /cards/abc.jpg -> object abc.jpg in the cards bucket
    matchRules: [{prefixMatch: /cards/}]
    service: ${P}/backendBuckets/${LB_CARDS_BACKEND}
    routeAction: {urlRewrite: {pathPrefixRewrite: /}}
  - priority: 4
    # The SPA entry point
    matchRules: [{fullPathMatch: /}]
    service: ${P}/backendBuckets/${LB_SITE_BACKEND}
    routeAction: {urlRewrite: {pathPrefixRewrite: /index.html}}
YAML
gcloud compute url-maps import "$LB_URL_MAP" "${G[@]}" --source="$GEN_DIR/url-map.yaml" --quiet

say "Managed certificate for $DOMAIN (provisioning takes 15-60 min)"
exists gcloud compute ssl-certificates describe "$LB_CERT" "${G[@]}" ||
  gcloud compute ssl-certificates create "$LB_CERT" "${G[@]}" --domains="$DOMAIN"

say "HTTPS proxy + forwarding rule :443"
exists gcloud compute target-https-proxies describe "$LB_HTTPS_PROXY" "${G[@]}" ||
  gcloud compute target-https-proxies create "$LB_HTTPS_PROXY" "${G[@]}" \
    --url-map="$LB_URL_MAP" --ssl-certificates="$LB_CERT"
exists gcloud compute forwarding-rules describe "$LB_HTTPS_RULE" "${G[@]}" ||
  gcloud compute forwarding-rules create "$LB_HTTPS_RULE" "${G[@]}" --load-balancing-scheme=EXTERNAL_MANAGED \
    --address="$LB_IP_NAME" --target-https-proxy="$LB_HTTPS_PROXY" --ports=443

say "HTTP :80 -> HTTPS redirect"
cat > "$GEN_DIR/redirect-map.yaml" <<YAML
name: ${LB_REDIRECT_MAP}
defaultUrlRedirect:
  httpsRedirect: true
  redirectResponseCode: MOVED_PERMANENTLY_DEFAULT
YAML
gcloud compute url-maps import "$LB_REDIRECT_MAP" "${G[@]}" --source="$GEN_DIR/redirect-map.yaml" --quiet
exists gcloud compute target-http-proxies describe "$LB_HTTP_PROXY" "${G[@]}" ||
  gcloud compute target-http-proxies create "$LB_HTTP_PROXY" "${G[@]}" --url-map="$LB_REDIRECT_MAP"
exists gcloud compute forwarding-rules describe "$LB_HTTP_RULE" "${G[@]}" ||
  gcloud compute forwarding-rules create "$LB_HTTP_RULE" "${G[@]}" --load-balancing-scheme=EXTERNAL_MANAGED \
    --address="$LB_IP_NAME" --target-http-proxy="$LB_HTTP_PROXY" --ports=80

say "Tell web its public origin (for og:image)"
gcloud run services update "$WEB_SERVICE" --region="$REGION" \
  --update-env-vars="PUBLIC_BASE_URL=https://${DOMAIN}" --quiet >/dev/null
echo "  https://${DOMAIN}"

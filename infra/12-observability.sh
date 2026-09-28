#!/usr/bin/env bash
# Log-based metrics from the JSON logs, an error-rate alert and a dashboard.
source "$(dirname "$0")/env.sh"
RUN='resource.type="cloud_run_revision"'

upsert_metric() {  # name, config file
  if exists gcloud logging metrics describe "$1"; then
    gcloud logging metrics update "$1" --config-from-file="$2" >/dev/null
  else
    gcloud logging metrics create "$1" --config-from-file="$2" >/dev/null
  fi
  echo "  metric $1"
}

counter() {  # name, description, filter
  cat > "$GEN_DIR/$1.yaml" <<YAML
description: $2
filter: '$3'
metricDescriptor: {metricKind: DELTA, valueType: INT64, unit: "1"}
YAML
  upsert_metric "$1" "$GEN_DIR/$1.yaml"
}

say "Log-based metrics"
counter roastfolio_roasts_queued "Roasts created (web)" \
  "$RUN AND resource.labels.service_name=\"$WEB_SERVICE\" AND jsonPayload.event=\"roast_queued\""
counter roastfolio_roasts_done "Roasts finished OK (worker)" \
  "$RUN AND resource.labels.service_name=\"$WORKER_SERVICE\" AND jsonPayload.event=\"roast_done\""
counter roastfolio_roasts_failed "Roasts marked failed (worker)" \
  "$RUN AND resource.labels.service_name=\"$WORKER_SERVICE\" AND jsonPayload.event=\"roast_failed\""
counter roastfolio_cards_generic "Roasts that got the generic certificate because Nano Banana failed (worker)" \
  "$RUN AND resource.labels.service_name=\"$WORKER_SERVICE\" AND jsonPayload.event=\"card_fallback\""

cat > "$GEN_DIR/roastfolio_step_duration.yaml" <<YAML
description: Duration of each pipeline step (extracting, roasting, rendering)
filter: '$RUN AND resource.labels.service_name="$WORKER_SERVICE" AND jsonPayload.event="step_finished"'
valueExtractor: EXTRACT(jsonPayload.durationMs)
labelExtractors:
  step: EXTRACT(jsonPayload.step)
metricDescriptor:
  metricKind: DELTA
  valueType: DISTRIBUTION
  unit: ms
  labels:
  - {key: step, valueType: STRING, description: Pipeline step}
bucketOptions:
  exponentialBuckets: {numFiniteBuckets: 24, growthFactor: 1.5, scale: 100}
YAML
upsert_metric roastfolio_step_duration "$GEN_DIR/roastfolio_step_duration.yaml"

say "Email notification channel"
CHANNEL="$(gcloud beta monitoring channels list --filter="displayName=\"Roastfolio alerts\"" --format='value(name)' | head -1)"
if [[ -z "$CHANNEL" ]]; then
  CHANNEL="$(gcloud beta monitoring channels create --display-name="Roastfolio alerts" --type=email \
    --channel-labels="email_address=$ALERT_EMAIL" --format='value(name)')"
fi
echo "  $CHANNEL"

say "Alert: error rate > 10% in 15 min (only with >= 5 roasts, so one failure at 3 a.m. doesn't page)"
F='logging_googleapis_com:user_roastfolio_roasts_failed'
D='logging_googleapis_com:user_roastfolio_roasts_done'
FAILED="(sum(increase(${F}[15m])) or vector(0))"
TOTAL="(${FAILED} + (sum(increase(${D}[15m])) or vector(0)))"
QUERY="(${FAILED} / ${TOTAL} > 0.1) and on() (${TOTAL} >= 5)"
python3 - "$GEN_DIR/alert.json" "$QUERY" "$CHANNEL" <<'PY'
import json, sys
path, query, channel = sys.argv[1:]
json.dump({
  "displayName": "Roastfolio: tasa de error > 10% (15 min)",
  "combiner": "OR",
  "conditions": [{
    "displayName": "failed / (done + failed) > 10%",
    "conditionPrometheusQueryLanguage": {"query": query, "duration": "0s", "evaluationInterval": "60s"},
  }],
  "notificationChannels": [channel],
  "alertStrategy": {"autoClose": "1800s"},
  "documentation": {
    "mimeType": "text/markdown",
    "content": "Más del 10% de los roasts fallaron en 15 minutos.\n\n"
               "Revisa los logs: `resource.labels.service_name=\"roastfolio-worker\" jsonPayload.event=\"roast_failed\"`",
  },
}, open(path, "w"), indent=2)
PY
for old in $(gcloud monitoring policies list --filter='displayName="Roastfolio: tasa de error > 10% (15 min)"' --format='value(name)'); do
  gcloud monitoring policies delete "$old" --quiet >/dev/null
done
gcloud monitoring policies create --policy-from-file="$GEN_DIR/alert.json" --format='value(name)'

say "Dashboard"
python3 - "$GEN_DIR/dashboard.json" "$LB_URL_MAP" "$QUEUE" <<'PY'
import json, sys
path, url_map, queue = sys.argv[1:]

def chart(title, queries, x, y, w=6, h=4, plot="LINE"):
    return {"xPos": x, "yPos": y, "width": w, "height": h, "widget": {
        "title": title,
        "xyChart": {"dataSets": [
            {"timeSeriesQuery": {"prometheusQuery": q}, "plotType": plot, "legendTemplate": legend}
            for q, legend in queries]}}}

lb = f'loadbalancing_googleapis_com:https_request_count{{monitored_resource="https_lb_rule",url_map_name="{url_map}"}}'
tiles = [
    chart("Roasts por hora", [
        ("sum(increase(logging_googleapis_com:user_roastfolio_roasts_done[1h]))", "done"),
        ("sum(increase(logging_googleapis_com:user_roastfolio_roasts_failed[1h]))", "failed"),
    ], 0, 0, plot="STACKED_BAR"),
    chart("Latencia por paso, p95 (ms)", [(
        "histogram_quantile(0.95, sum by (step, le) "
        "(rate(logging_googleapis_com:user_roastfolio_step_duration_bucket[30m])))", "${labels.step}")], 6, 0),
    chart("CDN: cache hit ratio (site + cards)", [(
        f'sum(rate({lb[:-1]},cache_result="HIT"}}[10m])) / '
        f'sum(rate({lb[:-1]},cache_result!="DISABLED"}}[10m]))', "hit ratio")], 0, 4),
    chart("Peticiones por resultado de caché", [(
        f"sum by (cache_result) (rate({lb}[5m]))", "${labels.cache_result}")], 6, 4, plot="STACKED_AREA"),
    chart("Respuestas del LB por código", [(
        f"sum by (response_code_class) (rate({lb}[5m]))", "${labels.response_code_class}")], 0, 8),
    chart("Cloud Tasks: tareas en cola", [(
        f'sum(cloudtasks_googleapis_com:queue_depth{{queue_id="{queue}"}})', "depth")], 6, 8),
]
json.dump({"displayName": "Roastfolio", "mosaicLayout": {"columns": 12, "tiles": tiles}}, open(path, "w"), indent=2)
PY
for old in $(gcloud monitoring dashboards list --filter='displayName="Roastfolio"' --format='value(name)'); do
  gcloud monitoring dashboards delete "$old" --quiet >/dev/null
done
DASH="$(gcloud monitoring dashboards create --config-from-file="$GEN_DIR/dashboard.json" --format='value(name)')"
echo "  https://console.cloud.google.com/monitoring/dashboards/builder/${DASH##*/}?project=$PROJECT_ID"

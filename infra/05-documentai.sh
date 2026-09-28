#!/usr/bin/env bash
# Document AI Layout Parser processor in the `us` multi-region. gcloud has no command for it, so REST.
source "$(dirname "$0")/env.sh"

API="https://${DOCAI_LOCATION}-documentai.googleapis.com/v1/projects/${PROJECT_ID}/locations/${DOCAI_LOCATION}/processors"
TOKEN="$(gcloud auth print-access-token)"

find_processor() {
  curl -sf -H "Authorization: Bearer $TOKEN" "$API" |
    python3 -c "import json,sys; ps=json.load(sys.stdin).get('processors',[]); print(next((p['name'].split('/')[-1] for p in ps if p.get('displayName')=='$DOCAI_PROCESSOR_NAME'), ''))"
}

say "Layout Parser processor"
ID="$(find_processor)"
if [[ -z "$ID" ]]; then
  curl -sf -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" "$API" \
    -d "{\"type\": \"LAYOUT_PARSER_PROCESSOR\", \"displayName\": \"$DOCAI_PROCESSOR_NAME\"}" >/dev/null
  ID="$(find_processor)"
fi
echo "$ID" > "$GEN_DIR/docai-processor-id"
echo "  processor id: $ID"

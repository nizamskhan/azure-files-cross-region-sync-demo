#!/usr/bin/env sh
set -eu

: "${SOURCE_URL:?SOURCE_URL is required.}"

DATA_DIR="/tmp/dummy-data"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$DATA_DIR/reports" "$DATA_DIR/docs" "$DATA_DIR/logs" "$DATA_DIR/json"

cat > "$DATA_DIR/reports/operations-summary-${RUN_ID}.txt" <<DATA
Operations summary
Generated at: ${RUN_ID}
Purpose: Synthetic unstructured data for Azure Files private endpoint sync testing.
DATA

cat > "$DATA_DIR/docs/customer-notes-${RUN_ID}.rtf" <<DATA
{\\rtf1\\ansi\\deff0 {\\fonttbl {\\f0 Calibri;}}
\\f0\\fs24 Synthetic customer notes generated at ${RUN_ID}.\\par
This file was uploaded from a temporary Azure Container Apps Job over a private endpoint.\\par
}
DATA

cat > "$DATA_DIR/docs/private-endpoint-demo-${RUN_ID}.html" <<DATA
<!doctype html><html><body><h1>Private Endpoint Demo</h1><p>Generated at ${RUN_ID}</p></body></html>
DATA

cat > "$DATA_DIR/json/metadata-${RUN_ID}.json" <<DATA
{"generatedAt":"${RUN_ID}","scenario":"private-endpoint-containerapp-job","purpose":"dummy-source-data"}
DATA

for i in 1 2 3 4 5; do
  printf '%s INFO Synthetic application event %s\n' "$RUN_ID" "$i" >> "$DATA_DIR/logs/application-${RUN_ID}.log"
done

head -c 32768 /dev/urandom | base64 > "$DATA_DIR/docs/random-payload-${RUN_ID}.txt"

azcopy copy "$DATA_DIR" "$SOURCE_URL" --recursive=true --from-to=LocalFile

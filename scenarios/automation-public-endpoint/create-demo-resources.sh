#!/usr/bin/env bash
set -euo pipefail

: "${SUBSCRIPTION_ID:?Set SUBSCRIPTION_ID before running this script.}"
: "${RG:=rg-azfilescrosregionsyncdemo}"
: "${PREFIX:?Set PREFIX to a globally unique lowercase value.}"
: "${SRC_STORAGE:=${PREFIX}src}"
: "${DST_STORAGE:=${PREFIX}dst}"
: "${AUTOMATION_ACCOUNT:=${PREFIX}aa}"
: "${SRC_SHARE:=sourcefiles}"
: "${DST_SHARE:=destfiles}"
: "${RUNBOOK:=Sync-AzureFiles-WestEurope-To-NorthEurope}"
: "${SCHEDULE:=Every-3-Hours}"

az account set --subscription "$SUBSCRIPTION_ID"

az group create \
  --name "$RG" \
  --location westeurope

az storage account create \
  --name "$SRC_STORAGE" \
  --resource-group "$RG" \
  --location westeurope \
  --kind FileStorage \
  --sku Premium_LRS \
  --https-only true \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false

az storage account create \
  --name "$DST_STORAGE" \
  --resource-group "$RG" \
  --location northeurope \
  --kind FileStorage \
  --sku Premium_LRS \
  --https-only true \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false

az storage share-rm create \
  --resource-group "$RG" \
  --storage-account "$SRC_STORAGE" \
  --name "$SRC_SHARE" \
  --quota 100 \
  --enabled-protocols SMB

az storage share-rm create \
  --resource-group "$RG" \
  --storage-account "$DST_STORAGE" \
  --name "$DST_SHARE" \
  --quota 100 \
  --enabled-protocols SMB

az automation account create \
  --resource-group "$RG" \
  --name "$AUTOMATION_ACCOUNT" \
  --location westeurope

AUTOMATION_ID=$(az automation account show \
  --resource-group "$RG" \
  --name "$AUTOMATION_ACCOUNT" \
  --query id -o tsv)

az resource update \
  --ids "$AUTOMATION_ID" \
  --set identity.type=SystemAssigned

MI_PRINCIPAL_ID=""
for _ in {1..30}; do
  MI_PRINCIPAL_ID=$(az resource show --ids "$AUTOMATION_ID" --query identity.principalId -o tsv)
  if [[ -n "$MI_PRINCIPAL_ID" && "$MI_PRINCIPAL_ID" != "null" ]]; then
    break
  fi
  sleep 10
done

if [[ -z "$MI_PRINCIPAL_ID" || "$MI_PRINCIPAL_ID" == "null" ]]; then
  echo "Managed identity principalId was not assigned." >&2
  exit 1
fi

SRC_ID=$(az storage account show --resource-group "$RG" --name "$SRC_STORAGE" --query id -o tsv)
DST_ID=$(az storage account show --resource-group "$RG" --name "$DST_STORAGE" --query id -o tsv)

az role assignment create \
  --assignee-object-id "$MI_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage File Data Privileged Reader" \
  --scope "$SRC_ID" \
  -o none

az role assignment create \
  --assignee-object-id "$MI_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage File Data Privileged Contributor" \
  --scope "$DST_ID" \
  -o none

RUNBOOK_PATH="runbooks/${RUNBOOK}.ps1"
TMP_RUNBOOK=$(mktemp)
sed \
  -e "s|https://<source-storage-account>.file.core.windows.net/<source-share>|https://${SRC_STORAGE}.file.core.windows.net/${SRC_SHARE}|g" \
  -e "s|https://<destination-storage-account>.file.core.windows.net/<destination-share>|https://${DST_STORAGE}.file.core.windows.net/${DST_SHARE}|g" \
  "$RUNBOOK_PATH" > "$TMP_RUNBOOK"

az automation runbook create \
  --resource-group "$RG" \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --name "$RUNBOOK" \
  --type PowerShell \
  --description "Sync Azure Files from West Europe to North Europe with AzCopy and managed identity."

az automation runbook replace-content \
  --resource-group "$RG" \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --name "$RUNBOOK" \
  --content "@${TMP_RUNBOOK}"

az automation runbook publish \
  --resource-group "$RG" \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --name "$RUNBOOK"

rm -f "$TMP_RUNBOOK"

START_TIME=$(date -u -v+10M '+%Y-%m-%d %H:%M:%S +00:00' 2>/dev/null || date -u -d '+10 minutes' '+%Y-%m-%d %H:%M:%S +00:00')

az automation schedule create \
  --resource-group "$RG" \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --name "$SCHEDULE" \
  --frequency Hour \
  --interval 3 \
  --start-time "$START_TIME" \
  --time-zone UTC

JOB_SCHEDULE_ID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)

az rest --method put \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/jobSchedules/${JOB_SCHEDULE_ID}?api-version=2023-11-01" \
  --body "{\"properties\":{\"runbook\":{\"name\":\"${RUNBOOK}\"},\"schedule\":{\"name\":\"${SCHEDULE}\"}}}"

cat <<EOF
Deployment complete.

Resource group:         ${RG}
Source storage account: ${SRC_STORAGE}
Source share:           ${SRC_SHARE}
Destination storage:    ${DST_STORAGE}
Destination share:      ${DST_SHARE}
Automation account:     ${AUTOMATION_ACCOUNT}
Runbook:                ${RUNBOOK}
Schedule:               ${SCHEDULE}
Job schedule ID:        ${JOB_SCHEDULE_ID}
EOF


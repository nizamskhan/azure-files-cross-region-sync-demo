#!/usr/bin/env bash
set -euo pipefail

: "${SUBSCRIPTION_ID:?Set SUBSCRIPTION_ID before running this script.}"
: "${RG:=rg-azfiles-private-sync-demo}"
: "${PREFIX:?Set PREFIX to the same value used by deploy-private-containerapp-job.sh.}"
: "${SRC_STORAGE:=${PREFIX}src}"
: "${SRC_SHARE:=sourcefiles}"
: "${SAMPLE_DATA_DIR:=sample-data}"

az account set --subscription "$SUBSCRIPTION_ID"

USER_ID=$(az ad signed-in-user show --query id -o tsv)
SRC_ID=$(az storage account show --resource-group "$RG" --name "$SRC_STORAGE" --query id -o tsv)

az role assignment create \
  --assignee-object-id "$USER_ID" \
  --assignee-principal-type User \
  --role "Storage File Data Privileged Contributor" \
  --scope "$SRC_ID" \
  -o none 2>/dev/null || true

echo "Waiting briefly for Azure RBAC propagation..."
sleep 30

echo "This upload must run from a network that can resolve and reach the source storage private endpoint."

az storage file upload-batch \
  --auth-mode login \
  --enable-file-backup-request-intent \
  --account-name "$SRC_STORAGE" \
  --destination "$SRC_SHARE" \
  --source "$SAMPLE_DATA_DIR"

echo "Sample data uploaded to ${SRC_STORAGE}/${SRC_SHARE}."

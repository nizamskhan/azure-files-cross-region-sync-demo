#!/usr/bin/env bash
set -euo pipefail

: "${SUBSCRIPTION_ID:?Set SUBSCRIPTION_ID before running this script.}"
: "${RG:=rg-azfiles-private-sync-demo}"
: "${PREFIX:?Set PREFIX to the same value used by deploy-private-containerapp-job.sh.}"
: "${SRC_STORAGE:=${PREFIX}src}"
: "${SRC_SHARE:=sourcefiles}"
: "${ACR_NAME:=${PREFIX}acr}"
: "${IDENTITY_NAME:=${PREFIX}-sync-mi}"
: "${CONTAINERAPPS_ENV:=${PREFIX}-cae}"
: "${GENERATOR_JOB:=${PREFIX}-gen}"
: "${CLEANUP_GENERATOR:=true}"

IMAGE_NAME="source-data-generator"
IMAGE_TAG="v1"

az account set --subscription "$SUBSCRIPTION_ID"

ACR_LOGIN_SERVER=$(az acr show --resource-group "$RG" --name "$ACR_NAME" --query loginServer -o tsv)
IDENTITY_ID=$(az identity show --resource-group "$RG" --name "$IDENTITY_NAME" --query id -o tsv)
IDENTITY_CLIENT_ID=$(az identity show --resource-group "$RG" --name "$IDENTITY_NAME" --query clientId -o tsv)
SOURCE_URL="https://${SRC_STORAGE}.file.core.windows.net/${SRC_SHARE}"

az acr build \
  --registry "$ACR_NAME" \
  --image "${IMAGE_NAME}:${IMAGE_TAG}" \
  ./container/source-data-generator

if az containerapp job show --resource-group "$RG" --name "$GENERATOR_JOB" -o none 2>/dev/null; then
  az containerapp job delete --resource-group "$RG" --name "$GENERATOR_JOB" --yes -o none
fi

az containerapp job create \
  --resource-group "$RG" \
  --name "$GENERATOR_JOB" \
  --environment "$CONTAINERAPPS_ENV" \
  --trigger-type Manual \
  --replica-timeout 1800 \
  --replica-retry-limit 0 \
  --replica-completion-count 1 \
  --parallelism 1 \
  --image "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}" \
  --mi-user-assigned "$IDENTITY_ID" \
  --registry-server "$ACR_LOGIN_SERVER" \
  --registry-identity "$IDENTITY_ID" \
  --env-vars \
    "SOURCE_URL=${SOURCE_URL}" \
    "AZCOPY_AUTO_LOGIN_TYPE=MSI" \
    "AZCOPY_MSI_CLIENT_ID=${IDENTITY_CLIENT_ID}" \
  -o none

EXECUTION_NAME=$(az containerapp job start \
  --resource-group "$RG" \
  --name "$GENERATOR_JOB" \
  --query name -o tsv)

for _ in {1..60}; do
  STATUS=$(az containerapp job execution show \
    --resource-group "$RG" \
    --name "$GENERATOR_JOB" \
    --job-execution-name "$EXECUTION_NAME" \
    --query properties.status -o tsv 2>/dev/null || true)

  echo "Execution ${EXECUTION_NAME}: ${STATUS}"

  case "$STATUS" in
    Succeeded|Failed|Canceled)
      break
      ;;
  esac

  sleep 10
done

az containerapp job execution show \
  --resource-group "$RG" \
  --name "$GENERATOR_JOB" \
  --job-execution-name "$EXECUTION_NAME" \
  --query '{name:name,status:properties.status,start:properties.startTime,end:properties.endTime}' \
  -o table

az containerapp job logs show \
  --resource-group "$RG" \
  --name "$GENERATOR_JOB" \
  --execution "$EXECUTION_NAME" \
  --container "$GENERATOR_JOB" \
  --tail 120 || true

FINAL_STATUS=$(az containerapp job execution show \
  --resource-group "$RG" \
  --name "$GENERATOR_JOB" \
  --job-execution-name "$EXECUTION_NAME" \
  --query properties.status -o tsv)

if [[ "$FINAL_STATUS" != "Succeeded" ]]; then
  echo "Dummy data generation failed with status ${FINAL_STATUS}." >&2
  exit 1
fi

if [[ "$CLEANUP_GENERATOR" == "true" ]]; then
  az containerapp job delete --resource-group "$RG" --name "$GENERATOR_JOB" --yes -o none
  az acr repository delete --name "$ACR_NAME" --repository "$IMAGE_NAME" --yes 2>/dev/null || true
fi

echo "Dummy source data uploaded to ${SOURCE_URL}."

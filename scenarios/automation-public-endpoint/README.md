# Scenario 1 - Automation Account Runbook with Public Storage Endpoints

This scenario uses an Azure Automation Account PowerShell runbook to run AzCopy every three hours.

Use this scenario only when the source and destination Azure Files endpoints are reachable from the Azure Automation cloud sandbox. If the storage accounts have public network access disabled, use the private endpoint Container Apps Job scenario instead.

## Included files

| File | Purpose |
|---|---|
| `create-demo-resources.sh` | Creates the original public-endpoint demo resources. |
| `upload-sample-data.sh` | Uploads sample data to the source share. |
| `runbooks/Sync-AzureFiles-WestEurope-To-NorthEurope.ps1` | PowerShell runbook that downloads AzCopy and copies files. |

## AzCopy command

```powershell
azcopy login --identity
azcopy sync <source-file-share-url> <destination-file-share-url> --recursive=true --from-to=FileFile --delete-destination=true
```

## Limitation

This pattern does not work for private-only storage endpoints unless Azure Automation is extended with a Hybrid Runbook Worker running inside a network that can reach the private endpoints.

## Mirror behavior

The runbook uses `azcopy sync --delete-destination=true`, so the destination share is treated as an exact mirror of the source share. Files that exist only in the destination are deleted.

# Azure Files Cross-Region Sync Demo

This repository contains implementation patterns for copying Azure Files from one Azure region to another using AzCopy and Microsoft Entra authentication.

## Scenarios

| Scenario | Use when | Location |
|---|---|---|
| Automation Account runbook | Storage accounts can be reached through their public Azure Files endpoints. | `scenarios/automation-public-endpoint/` |
| Private endpoint Container Apps Job | Storage accounts have public network access disabled and are reachable only through private endpoints. | `scenarios/private-endpoint-containerapp-job/` |

## Recommendation

Use the **private endpoint Container Apps Job** scenario when storage accounts are locked down with private endpoints. Azure Automation cloud sandboxes are not deployed into your VNet, so they cannot reach private-only storage endpoints unless you use a Hybrid Runbook Worker or another private compute option.

## Security model

Both scenarios avoid storage account SAS tokens in the scheduled copy workflow. The scheduled compute authenticates with managed identity and uses Azure Files data-plane RBAC.

# ADR-006: Infrastructure as Code Tooling

**Status:** Accepted  
**Date:** 2026-03-03  
**Deciders:** Lead Azure Architect

## Context
The platform requires all infrastructure defined as code with:
- No manual portal changes (enforced via Azure Policy)
- Modular, reusable structure
- Native integration with Azure deployment pipeline
- Support for what-if previews before apply
- State management that doesn't introduce operational risk

## Decision
**Azure Bicep with subscription-scope modular deployment**

## Alternatives Considered

| Tool | State Management | Azure Native | Learning Curve | Multi-Cloud | Decision |
|---|---|---|---|---|---|
| Bicep | None (ARM state) | First-class | Low for Azure teams | No | Accepted |
| Terraform (AzureRM) | Remote state (Storage) | Good | Medium | Yes | Rejected for this project |
| Terraform (AzAPI) | Remote state (Storage) | Excellent | High | Yes | Rejected for this project |
| ARM Templates (JSON) | None | First-class | High (verbose) | No | Rejected |
| Pulumi | None / remote | Good | High | Yes | Rejected |
| Azure CLI scripts | None | First-class | Low | No | Rejected |

## Rationale

**Why Bicep over Terraform:**
This is a pure Azure workload with no multi-cloud requirement. Bicep compiles 
directly to ARM, has zero state file management overhead, and supports every 
Azure resource on day-one release (Terraform AzureRM provider often lags by 
weeks on new resource types). The subscription-scope deployment model maps 
naturally to Bicep's targetScope feature.

Terraform would be the correct choice if:
- Multiple cloud providers are required in the same platform
- The team has existing Terraform expertise and state management infrastructure
- The workload spans multiple subscriptions requiring cross-subscription state

**Why modular structure:**
Each module owns one resource type (networking, keyvault, appservice etc).
This enforces single-responsibility, enables independent testing, and allows 
modules to be reused across environments by passing different parameters.
main.bicep is a pure orchestrator — it contains no resource definitions.

**Why subscription scope for main.bicep:**
Deploying at subscription scope allows main.bicep to create resource groups 
and deploy resources into them in a single operation. The alternative 
(pre-creating resource groups separately) splits infrastructure management 
across multiple commands and breaks the "single command to deploy" principle.

**Azure Policy enforcement:**
Bicep alone cannot prevent someone from making manual portal changes.
Azure Policy with deny effects ensures IaC is the only path to change:
- Deny resources without required tags (ManagedBy: Bicep)
- Deny public endpoints on Key Vault, SQL, Storage
- Deny resources outside approved regions

## Consequences
- **Positive:** Zero state file management — no storage account, no locking, no drift reconciliation
- **Positive:** What-if preview built in (az deployment sub what-if)
- **Positive:** First-class Azure support — new resource types available immediately
- **Positive:** Bicep linter catches misconfigurations at development time
- **Negative:** Azure-only — cannot reuse modules for AWS/GCP resources
- **Negative:** Smaller community than Terraform (fewer Stack Overflow answers)
- **Risk:** Bicep is a Microsoft product — roadmap dependent on Microsoft investment

## Module Structure
```
infra/bicep/
├── main.bicep              # Subscription-scope orchestrator, no resource definitions
├── parameters/
│   ├── dev.bicepparam      # Dev environment values
│   └── prod.bicepparam     # Prod environment values  
└── modules/
    ├── networking.bicep    # Hub-spoke VNets, NSGs, peering, DNS zones
    ├── keyvault.bicep      # Key Vault, private endpoint, RBAC
    ├── monitoring.bicep    # Log Analytics, App Insights, Action Group
    ├── alerts.bicep        # KQL alert rules (deployed post-app)
    ├── appservice.bicep    # App Service Plan, Web App, slots
    ├── apim.bicep          # API Management, products, subscriptions
    ├── sql.bicep           # Azure SQL, geo-replication
    ├── servicebus.bicep    # Service Bus, Geo-DR
    ├── redis.bicep         # Azure Cache for Redis
    └── rbac.bicep          # Role assignments (avoids circular deps)
```

## References
- [Bicep documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [Bicep vs Terraform comparison](https://learn.microsoft.com/azure/azure-resource-manager/bicep/compare-template-syntax)
- [Subscription scope deployments](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-to-subscription)
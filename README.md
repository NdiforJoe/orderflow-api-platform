# OrderFlow API Platform Governance Accelerator

> **A principal-level Azure architecture portfolio project** demonstrating secure, governed API modernisation — from legacy monolith to Azure-native platform with zero-trust networking, DevSecOps automation, and full observability.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![IaC: Bicep](https://img.shields.io/badge/IaC-Bicep-0078D4)](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
[![Platform: Azure](https://img.shields.io/badge/Platform-Azure-0078D4)](https://azure.microsoft.com)
[![WAF Aligned](https://img.shields.io/badge/WAF-Aligned-green)](https://learn.microsoft.com/azure/well-architected/)
[![CI](https://github.com/NdiforJoe/orderflow-api-platform/actions/workflows/ci-security-scan.yml/badge.svg)](https://github.com/NdiforJoe/orderflow-api-platform/actions/workflows/ci-security-scan.yml)

---

## Table of Contents

- [Business Context](#business-context)
- [Architecture Overview](#architecture-overview)
- [Deployed Resources](#deployed-resources)
- [Azure Well-Architected Framework Alignment](#azure-well-architected-framework-alignment)
- [Repository Structure](#repository-structure)
- [Architecture Decision Records](#architecture-decision-records)
- [Prerequisites](#prerequisites)
- [Step-by-Step Deployment Guide](#step-by-step-deployment-guide)
  - [Phase 1 — Environment Setup](#phase-1--environment-setup)
  - [Phase 2 — Networking and Key Vault](#phase-2--networking-and-key-vault)
  - [Phase 3 — Monitoring and App Service](#phase-3--monitoring-and-app-service)
  - [Phase 4 — API Management](#phase-4--api-management)
  - [Phase 5 — Data Tier](#phase-5--data-tier)
  - [Phase 6 — DevSecOps Pipeline](#phase-6--devsecops-pipeline)
- [Known Limitations (Dev Environment)](#known-limitations-dev-environment)
- [Cost Estimates](#cost-estimates)
- [Cleanup](#cleanup)
- [Contributing](#contributing)

---

## Business Context

**The problem this solves:**

Contoso Manufacturing runs a monolithic Order Management System (OMS) on-premises with:

- No API governance — different auth mechanism per consuming team
- Zero observability — 4-hour mean time to detect (MTTD) for incidents
- Manual deployments — 6-hour maintenance windows, high change failure rate
- API keys stored in config files — violates ISO 27001 controls
- No network segmentation — a compromised service can reach everything
- Cannot scale — seasonal 10x traffic spikes cause outages

**What this platform delivers:**

A secure, governed Azure-native API platform where:

- Every API call flows through **Azure API Management** — single enforcement point for auth, rate limiting, and OWASP mitigations
- **Zero public backend IPs** — all services sit inside a hub-spoke VNet with private endpoints
- **Entra ID** handles all authentication (client credentials for B2B, auth code + PKCE for users)
- **Managed Identity** replaces every stored credential — no secrets in code or config
- Full platform provisioned via modular Bicep IaC with a single command
- **5-gate DevSecOps pipeline** — CodeQL, Snyk, Trivy, DAST, blue-green deploy with auto-rollback

---

## Architecture Overview

### High-Level Architecture

![High-Level Architecture](docs/diagrams/diagram1-network-topology.png)
*Figure 1: Hub-spoke zero-trust network topology. All external traffic enters via Azure Front Door → Azure Firewall → APIM (internal VNet mode) → App Service (VNet-integrated). No backend service has a public IP.*

### Security and Identity Flow

![Security and Identity Flow](docs/diagrams/diagram2-security-identity.png)
*Figure 2: Three auth flows — B2B client credentials, SPA auth code + PKCE, and service-to-service Managed Identity. APIM validates every JWT and strips it before forwarding to the backend.*

### DevSecOps CI/CD Pipeline

![CI/CD Pipeline](docs/diagrams/diagram3-cicd-pipeline.png)
*Figure 3: Five mandatory security gates before production. Blue-green slot swap with automated health check and instant rollback. OIDC federated login — no service principal secrets stored anywhere.*

### Disaster Recovery Topology

![DR Topology](docs/diagrams/diagram4-dr-topology.png)
*Figure 4: Warm standby in paired region (East US 2 → Central US). RTO < 15 min for app tier, < 60 min full platform. SQL geo-replication with < 5s RPO.*

---

## Deployed Resources

### What is live after all 6 phases

| Resource | Name | Tier | Notes |
|---|---|---|---|
| Resource Group (workload) | `rg-orderflow-dev` | — | East US 2 |
| Resource Group (network) | `rg-orderflow-network-dev` | — | East US 2 |
| Hub VNet | `vnet-hub-dev` | — | 10.0.0.0/16 |
| Spoke VNet | `vnet-spoke-dev` | — | 10.1.0.0/16 |
| NSGs | `nsg-apim-dev`, `nsg-app-dev`, `nsg-data-dev` | — | Deny-all baseline |
| Private DNS Zones | 5 zones | — | KV, SQL, Redis, SB, ACR |
| Key Vault | `kv-orderflow-dev-dev001` | Standard | Private endpoint, RBAC mode |
| Log Analytics | `log-orderflow-dev` | — | 30-day retention |
| App Insights | `appi-orderflow-dev` | — | Linked to Log Analytics |
| App Service Plan | `asp-orderflow-dev` | P1v4 | Linux |
| App Service | `app-orderflow-dev` | — | System MI, staging slot |
| API Management | `apim-orderflow-dev` | Developer | Internal VNet, `10.0.2.4` |
| Redis Cache | `redis-orderflow-dev` | C1 Standard | Private endpoint |
| Service Bus | `sb-orderflow-dev` | Standard | Orders topic + subscription |
| SQL Server | `sql-orderflow-dev` | — | Entra ID only auth |
| SQL Database | `db-orderflow-dev` | GP_S_Gen5 | Serverless, auto-pause 60 min |
| Container Registry | `acrdevdev001` | Basic | Admin disabled, AcrPull RBAC |

---

## Azure Well-Architected Framework Alignment

| Pillar | Decision | Evidence |
|---|---|---|
| **Reliability** | Zone-redundant App Service, SQL geo-replication, warm standby DR, blue-green deployments with auto-rollback | ADR-005, `appservice.bicep` |
| **Security** | Zero-trust network (no public IPs), Managed Identity everywhere, APIM OWASP policies, no stored credentials in pipeline | ADR-003, ADR-004, `networking.bicep`, APIM policy XML |
| **Cost Optimisation** | Dev tiers ~$117/mo, Serverless SQL auto-pauses in dev, Redis cache reduces SQL reads, 1-yr RI modelled for prod | ADR-001, ADR-002, `dev.bicepparam` |
| **Operational Excellence** | 100% IaC, GitOps, ADRs as living docs, 5-gate CI, DAST in CD, auto-rollback on health check failure | ADR-006, `main.bicep`, GitHub Actions pipelines |
| **Performance Efficiency** | APIM response caching (60s TTL), Redis cache-aside pattern, auto-scale 3–10 instances on CPU > 70% | `order-api-policy.xml`, `appservice.bicep` |

---

## Repository Structure

```
orderflow-api-platform/
│
├── infra/
│   └── bicep/
│       ├── main.bicep                    # Subscription-scope orchestrator
│       ├── parameters/
│       │   ├── dev.bicepparam
│       │   └── prod.bicepparam
│       └── modules/
│           ├── networking.bicep          # Hub-spoke VNets, NSGs, peering, DNS zones
│           ├── keyvault.bicep            # Key Vault, RBAC, private endpoint
│           ├── monitoring.bicep          # Log Analytics, App Insights, action groups
│           ├── appservice.bicep          # App Service Plan, Web App, MI, slots
│           ├── apim.bicep                # APIM, products, APIs, logger, named values
│           ├── sql.bicep                 # Azure SQL Server + Serverless database
│           ├── redis.bicep               # Azure Cache for Redis, private endpoint
│           ├── servicebus.bicep          # Service Bus, orders topic, subscription
│           ├── acr.bicep                 # Container Registry, AcrPull RBAC
│           └── rbac.bicep                # Key Vault Secrets User role assignments
│
├── src/
│   └── OrderManagement.Api/
│       ├── Program.cs                    # .NET 8 Minimal API, DefaultAzureCredential
│       ├── Endpoints/OrderEndpoints.cs   # CRUD, cache-aside, tenant-scoped queries
│       ├── Models/Order.cs               # Domain models + DTOs
│       ├── Data/OrderDbContext.cs        # EF Core, tenant-scoped indexes
│       ├── Services/OrderService.cs      # Cache-aside, audit trail
│       └── Dockerfile                    # Multi-stage Alpine, non-root uid 1000
│
├── apim-policies/
│   ├── global-policy.xml                 # Correlation ID, security headers, size limit
│   ├── order-api-policy.xml              # JWT validate, rate limit, caching, OWASP
│   └── products/
│       ├── internal-product-policy.xml   # 500 req/min
│       └── partner-product-policy.xml    # 60 req/min, 100k/month quota
│
├── .github/
│   └── workflows/
│       ├── ci-security-scan.yml          # Build, CodeQL, Snyk, Trivy, Bicep lint
│       └── cd-prod.yml                   # OIDC, ACR push, dev deploy, DAST, blue-green
│
├── docs/
│   ├── adrs/
│   │   ├── ADR-001-apim-tier-selection.md
│   │   ├── ADR-002-compute-platform.md
│   │   ├── ADR-003-network-topology.md
│   │   ├── ADR-004-authentication-strategy.md
│   │   ├── ADR-005-dr-strategy.md
│   │   └── ADR-006-iac-tooling.md
│   ├── diagrams/
│   └── screenshots/
│
└── scripts/
    ├── seed-keyvault-secrets.ps1         # Seeds SQL, Redis, SB connection strings
    ├── setup-entra-apps.ps1              # Creates Order API, Partner, SPA app regs
    └── cleanup.ps1                       # Tears down all resources
```

---

## Architecture Decision Records

| ADR | Decision | Key Trade-off |
|---|---|---|
| [ADR-001](docs/adrs/ADR-001-apim-tier-selection.md) | APIM Premium (prod) / Developer (dev) | Internal VNet mode required — rules out Consumption and Standard tiers |
| [ADR-002](docs/adrs/ADR-002-compute-platform.md) | App Service Premium v4 | Deployment slots for blue-green + zone redundancy; AKS rejected — overhead without benefit for single service |
| [ADR-003](docs/adrs/ADR-003-network-topology.md) | Hub-spoke with Azure Firewall | Reusable hub pattern; Firewall Premium justified by IDPS + TLS inspection in prod |
| [ADR-004](docs/adrs/ADR-004-authentication-strategy.md) | Entra ID + Managed Identity everywhere | Client credentials (B2B), auth code + PKCE (users), MI (service-to-service) — zero stored secrets |
| [ADR-005](docs/adrs/ADR-005-dr-strategy.md) | Warm standby — not active-active | Achieves RTO < 1hr at 25% of active-active cost (+$280/mo vs +$1,800/mo) |
| [ADR-006](docs/adrs/ADR-006-iac-tooling.md) | Bicep over Terraform | Pure Azure workload — no state file management, first-class Azure feature support |

---

## Prerequisites

### Tools Required

| Tool | Version | Install |
|---|---|---|
| Azure CLI | 2.60+ | [aka.ms/installazurecliwindows](https://aka.ms/installazurecliwindows) |
| Bicep CLI | 0.28+ | `az bicep install` |
| .NET SDK | 8.0+ | [dotnet.microsoft.com](https://dotnet.microsoft.com/download/dotnet/8.0) |
| Docker Desktop | 24.0+ | [docker.com](https://www.docker.com/products/docker-desktop) |
| Git | 2.40+ | [git-scm.com](https://git-scm.com) |
| VS Code | Latest | [code.visualstudio.com](https://code.visualstudio.com) |

### Azure Requirements

- Azure subscription (free trial works — ~$200 credit lasts ~50 days at dev burn rate)
- Contributor role on subscription
- Permission to create App Registrations in Entra ID

### Verify your environment

```powershell
az version
az bicep version
dotnet --version
docker --version
az account show --output table
```

---

## Step-by-Step Deployment Guide

> **Important:** Run all commands from the repo root. All commands are PowerShell on Windows.

---

### Phase 1 — Environment Setup

**What this phase does:** Installs tools, clones the repo, registers Azure resource providers.

```powershell
# 1. Clone the repo
git clone https://github.com/NdiforJoe/orderflow-api-platform.git
cd orderflow-api-platform

# 2. Log in to Azure
az login
az account show --output table

# 3. Register required resource providers
$providers = @(
    "Microsoft.Network", "Microsoft.Web", "Microsoft.ApiManagement",
    "Microsoft.KeyVault", "Microsoft.Sql", "Microsoft.Cache",
    "Microsoft.ServiceBus", "Microsoft.ContainerRegistry",
    "Microsoft.Insights", "Microsoft.OperationalInsights",
    "Microsoft.Security", "Microsoft.ManagedIdentity"
)
foreach ($provider in $providers) {
    Write-Host "Registering $provider..."
    az provider register --namespace $provider --wait
}
Write-Host "All providers registered" -ForegroundColor Green
```

---

### Phase 2 — Networking and Key Vault

**What this phase deploys:**
- Hub VNet (10.0.0.0/16): AzureFirewallSubnet, snet-apim, snet-shared-services, AzureBastionSubnet
- Spoke VNet (10.1.0.0/16): snet-app, snet-integration, snet-data
- 3 NSGs with explicit deny-all rules at priority 4096
- Bidirectional VNet peering with gateway transit
- 5 Private DNS zones linked to both VNets
- Key Vault (RBAC mode, public access disabled, private endpoint)
- Log Analytics Workspace + Application Insights + Action Group

**Cost: ~$0.08/day**

```powershell
# Lint
az bicep lint --file infra\bicep\main.bicep

# What-if dry run
az deployment sub what-if `
    --location "eastus2" `
    --template-file infra\bicep\main.bicep `
    --parameters infra\bicep\parameters\dev.bicepparam

# Deploy
az deployment sub create `
    --location "eastus2" `
    --template-file infra\bicep\main.bicep `
    --parameters infra\bicep\parameters\dev.bicepparam `
    --name "deploy-orderflow-dev-$(Get-Date -Format 'yyyyMMdd-HHmm')"

# Verify
az network vnet list --resource-group rg-orderflow-network-dev --output table
az network vnet peering list `
    --vnet-name vnet-hub-dev `
    --resource-group rg-orderflow-network-dev --output table
az keyvault list --resource-group rg-orderflow-dev --output table
az network private-endpoint list --resource-group rg-orderflow-dev --output table
```

**Expected:** Both VNets listed, peering in `Connected` state, Key Vault listed, private endpoint `Succeeded`.

> **Quota note:** If you hit `SubscriptionIsOverQuotaForSku`, go to portal → Subscriptions → Usage + quotas → request an increase on the `P0v4-P5mv4 VMs` row. Auto-approves instantly on Pay-As-You-Go.

---

### Phase 3 — Monitoring and App Service

**What this phase deploys:**
- App Service Plan P1v4 (Linux)
- Web App with system-assigned Managed Identity
- VNet integration → snet-app in spoke VNet
- Staging deployment slot (blue-green ready)
- MI → Key Vault Secrets User RBAC (production + staging slots)
- Diagnostic settings → Log Analytics

**Cost: ~$0.98/day cumulative**

```powershell
# Same incremental deploy command — Bicep only creates new resources
az deployment sub create `
    --location "eastus2" `
    --template-file infra\bicep\main.bicep `
    --parameters infra\bicep\parameters\dev.bicepparam `
    --name "deploy-orderflow-dev-$(Get-Date -Format 'yyyyMMdd-HHmm')"

# Verify
az webapp show `
    --name app-orderflow-dev `
    --resource-group rg-orderflow-dev `
    --query "{name:name, state:state, hostname:defaultHostName}" `
    --output table

az webapp deployment slot list `
    --name app-orderflow-dev `
    --resource-group rg-orderflow-dev --output table
```

**Expected:** Web app in `Running` state, staging slot listed.

---

### Phase 4 — API Management

**What this phase deploys:**
- APIM Developer tier, internal VNet mode (private IP: `10.0.2.4`)
- System-assigned Managed Identity
- App Insights logger linked to `appi-orderflow-dev`
- Named values: `backend-base-url`, `environment-name`
- Backend pointing to App Service
- Products: `internal` (500 req/min), `partner` (60 req/min + 100k/month quota)
- Order API at path `/orders`, subscription required
- TLS 1.0/1.1/SSL3 and TripleDes168 disabled

**Cost: ~$1.63/day cumulative**

> **Important:** APIM Developer tier takes **45–60 minutes** to provision. Do not cancel the deployment command.

```powershell
az deployment sub create `
    --location "eastus2" `
    --template-file infra\bicep\main.bicep `
    --parameters infra\bicep\parameters\dev.bicepparam `
    --name "deploy-orderflow-dev-$(Get-Date -Format 'yyyyMMdd-HHmm')"

# Verify
az apim show `
    --name apim-orderflow-dev `
    --resource-group rg-orderflow-dev `
    --query "properties.provisioningState" --output tsv
```

**Expected:** `Succeeded`

---

### Phase 5 — Data Tier

**What this phase deploys:**
- Azure SQL Server (Entra ID only auth, no SQL auth, public access disabled)
- Azure SQL Database `db-orderflow-dev` (Serverless GP_S_Gen5, auto-pause 60 min)
- Azure Cache for Redis C1 Standard (SSL only, LRU eviction, private endpoint)
- Service Bus Standard namespace (Entra ID only, no SAS keys)
- `orders` topic: 14-day TTL, duplicate detection
- `order-processing` subscription: dead-letter after 3 retries
- Container Registry Basic (admin disabled, AcrPull RBAC for App Service MI)
- Service Bus Data Sender RBAC for App Service MI

**Cost: ~$3.90/day cumulative (~$117/month)**

```powershell
az deployment sub create `
    --location "eastus2" `
    --template-file infra\bicep\main.bicep `
    --parameters infra\bicep\parameters\dev.bicepparam `
    --name "deploy-orderflow-dev-$(Get-Date -Format 'yyyyMMdd-HHmm')"

# Verify all data resources
az sql db show `
    --server sql-orderflow-dev --resource-group rg-orderflow-dev `
    --name db-orderflow-dev `
    --query "{name:name, status:status, sku:currentSku.name}" --output table

az redis show `
    --name redis-orderflow-dev --resource-group rg-orderflow-dev `
    --query "{name:name, provisioningState:provisioningState}" --output table

az servicebus namespace show `
    --name sb-orderflow-dev --resource-group rg-orderflow-dev `
    --query "{name:name, status:status}" --output table

az acr show `
    --name acrdevdev001 --resource-group rg-orderflow-dev `
    --query "{name:name, loginServer:loginServer}" --output table
```

**After deployment — seed Key Vault secrets:**

```powershell
.\scripts\seed-keyvault-secrets.ps1 -EnvironmentName dev
```

**Create Entra ID app registrations:**

```powershell
.\scripts\setup-entra-apps.ps1
```

Save the output — you will need `tenant-id` and `order-api-client-id` to update APIM named values.

---

### Phase 6 — DevSecOps Pipeline

**What this phase sets up:**
- GitHub Actions CI: Build → CodeQL SAST → Snyk SCA → Trivy container + IaC scan → Bicep lint
- GitHub Actions CD: OIDC login → ACR push → Dev deploy → DAST (OWASP ZAP) → Manual approval → Blue-green slot swap → Auto-rollback
- OIDC federated credentials — zero stored Azure credentials in GitHub
- Branch protection: CI must pass before merge to main

#### Step 1 — Create OIDC app registration

```powershell
$app = (az ad app create `
    --display-name "orderflow-github-actions" | ConvertFrom-Json)
$appId = $app.appId

az ad sp create --id $appId --output none
$spObjectId = (az ad sp show --id $appId --query id -o tsv)

az role assignment create `
    --assignee $spObjectId `
    --role "Contributor" `
    --scope "/subscriptions/$(az account show --query id -o tsv)" `
    --output none

Write-Host "App ID: $appId" -ForegroundColor Green
```

#### Step 2 — Create federated credentials

```powershell
$githubUsername = "YOUR-GITHUB-USERNAME"
$repoName = "orderflow-api-platform"

@"
{
  "name": "github-actions-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:$githubUsername/${repoName}:ref:refs/heads/main",
  "description": "GitHub Actions OIDC for main branch",
  "audiences": ["api://AzureADTokenExchange"]
}
"@ | Set-Content -Path "federated-main.json" -Encoding UTF8
az ad app federated-credential create --id $appId --parameters federated-main.json --output none

@"
{
  "name": "github-actions-pr",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:$githubUsername/${repoName}:pull_request",
  "description": "GitHub Actions OIDC for pull requests",
  "audiences": ["api://AzureADTokenExchange"]
}
"@ | Set-Content -Path "federated-pr.json" -Encoding UTF8
az ad app federated-credential create --id $appId --parameters federated-pr.json --output none

Remove-Item federated-main.json, federated-pr.json
Write-Host "Federated credentials created" -ForegroundColor Green
```

#### Step 3 — Configure GitHub

1. **Add secrets:** repo → Settings → Secrets and variables → Actions
   - `AZURE_CLIENT_ID` → value from Step 1
   - `SNYK_TOKEN` → from [snyk.io](https://snyk.io) → Account Settings → Auth Token

2. **Create environments:** Settings → Environments
   - `dev` — no protection rules
   - `production` — Required reviewers: add yourself

3. **Enable branch protection:** Settings → Branches → Add rule on `main`
   - Required status checks: `Build`, `CodeQL SAST`, `Bicep Lint`
   - Do not allow bypassing

4. **Trigger first CI run:** Actions → CI Security Scan → Run workflow

**Expected:** All 5 gates green.

---

## Known Limitations (Dev Environment)

Documented accepted trade-offs. All resolved in prod.

| Limitation | Reason | Prod Resolution |
|---|---|---|
| SQL Server in `westus2` | East US 2 region quota restriction at time of initial deployment | Deploy SQL in `eastus2` once quota available |
| SQL private endpoint disabled | Cross-region private endpoints not supported | Re-enable once SQL co-located with VNet |
| Service Bus private endpoint disabled | Standard tier does not support private endpoints | Upgrade to Premium tier in prod |
| ACR private endpoint disabled | Basic tier does not support private endpoints | Upgrade to Premium tier in prod |
| No Azure Firewall | Cost (~$2,500/mo) prohibitive for dev | Deploy Firewall Premium in prod (ADR-003) |
| App Service P1v4 | East US 2 only had v4 quota available on new subscription | Both tiers equivalent; v4 is newer generation |

---

## Cost Estimates

### Development Environment (~$117/month)

| Resource | Tier | Monthly Cost |
|---|---|---|
| APIM | Developer | ~$49 |
| App Service Plan | P1v4 | ~$49 |
| Redis Cache | C1 Standard | ~$55 |
| SQL Database | Serverless GP_S_Gen5 (auto-pause) | ~$5 |
| Service Bus | Standard | ~$10 |
| Key Vault | Standard | ~$1 |
| Log Analytics | Pay-per-GB | ~$5 |
| Container Registry | Basic | ~$5 |
| Private Endpoints + DNS | Standard | ~$10 |
| **Total** | | **~$117/month (~$3.90/day)** |

> **Free trial:** ~$200 credit lasts approximately 50 days at this burn rate.

### Production Environment (estimated)

| Resource | Tier | Monthly Cost |
|---|---|---|
| APIM | Premium 1 unit (1-yr RI) | ~$1,680 |
| App Service | P1v3 × 3 zone-redundant | ~$270 |
| SQL Database | Business Critical | ~$400 |
| Azure Firewall | Premium | ~$2,500 |
| Redis | P1 Premium | ~$250 |
| Service Bus | Premium | ~$700 |

> Reserved Instances on APIM Premium reduce cost ~40%. Azure Firewall is the largest line item — justified by IDPS + TLS inspection requirement in ADR-003.

---

## Cleanup

```powershell
az group delete --name "rg-orderflow-network-dev" --yes --no-wait
az group delete --name "rg-orderflow-dev" --yes --no-wait

Write-Host "Cleanup initiated. Resources deleting in background (~3-5 min)." -ForegroundColor Yellow

# Verify
az group list --query "[?contains(name, 'orderflow')]" --output table
```

> **Key Vault soft-delete:** 7-day retention. If redeploying within 7 days, purge first:
> ```powershell
> az keyvault purge --name kv-orderflow-dev-dev001 --location eastus2
> ```

> **APIM re-deploy:** Developer tier takes 45–60 minutes to re-provision.

---

## Contributing

- Add an ADR for any new architectural decision
- Update the WAF alignment table for any new pillar decision
- Add screenshots for any new phase you complete
- Keep Bicep modules single-responsibility — one module per resource type
- All CI gates must pass before merging to main

---

## License

MIT — see [LICENSE](LICENSE)

---

*Built as a portfolio project demonstrating principal-level Azure architecture. All company names (Contoso Manufacturing) are fictional.*

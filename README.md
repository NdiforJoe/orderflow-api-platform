# OrderFlow API Platform Governance Accelerator

> Principal-level Azure architecture portfolio project demonstrating secure, governed API modernization.

## Business Context
Contoso Manufacturing migrates a legacy monolithic Order Management System to a secure Azure-native API platform governed by Azure API Management, zero-trust networking, and full DevSecOps automation.

## Architecture Highlights
- **APIM** as single enforcement point (JWT validation, rate limiting, OWASP mitigations)
- **Hub-spoke VNet** with Azure Firewall Premium and all PaaS via private endpoints
- **Entra ID** OAuth2 (client credentials + auth code + PKCE)
- **Modular Bicep** IaC with Azure Policy guardrails
- **5-gate DevSecOps pipeline** (CodeQL, Snyk, Trivy, ZAP DAST, blue-green deploy)

## Azure Well-Architected Framework Alignment
| Pillar | Key Decisions |
|---|---|
| Reliability | Zone-redundant App Service, SQL geo-replication, warm standby DR (ADR-005) |
| Security | Zero-trust network, Managed Identity everywhere, APIM OWASP policies (ADR-003, ADR-004) |
| Cost Optimization | Dev tiers ~/mo, prod ~/mo, Reserved Instance modelled |
| Operational Excellence | 100% IaC, GitOps, blue-green deployments, ADRs as living docs |
| Performance Efficiency | APIM response caching, Redis cache-aside, auto-scale 3-10 instances |

## Repository Structure
- /infra/bicep - Modular Bicep IaC (main + 10 child modules)
- /src - .NET 8 Order Management API
- /apim-policies - APIM policy XML files
- /docs/adrs - Architecture Decision Records
- /docs/diagrams - Architecture diagrams
- /scripts - Setup and cleanup scripts

## Cost Estimate (Dev Tier)
~/month. Run cleanup.ps1 to tear down all resources.

## ADRs
- ADR-001: APIM Tier Selection
- ADR-002: Compute Platform Selection
- ADR-003: Network Topology
- ADR-004: Authentication Strategy
- ADR-005: Disaster Recovery Strategy
- ADR-006: IaC Tooling

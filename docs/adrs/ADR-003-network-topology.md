# ADR-003: Network Topology

**Status:** Accepted  
**Date:** 2026-03-03  
**Deciders:** Lead Azure Architect

## Context
The platform must enforce zero-trust networking:
- No backend service reachable from public internet
- All PaaS services (Key Vault, SQL, Redis, Service Bus) accessible only via private endpoints
- Traffic inspection capability for compliance
- Reusable pattern for future workloads in the same tenant

## Decision
**Hub-spoke VNet topology with NSG-enforced segmentation**

Hub VNet (10.0.0.0/16): APIM subnet, shared services, Bastion, Firewall  
Spoke VNet (10.1.0.0/16): App subnet, integration subnet, data subnet  
All PaaS services connected via private endpoints in shared services and data subnets

## Alternatives Considered

| Option | Cost | Isolation | Reusability | Decision |
|---|---|---|---|---|
| Hub-spoke with Azure Firewall Premium | ~$2,500/mo | Full IDPS + TLS inspection | High | Accepted for prod, omitted dev (cost) |
| Hub-spoke with NSGs only | ~$0 | Network segmentation only | High | Accepted for dev |
| Flat VNet with NSGs | ~$0 | Limited | Low | Rejected |
| No VNet (public endpoints + firewall rules) | ~$0 | Low | None | Rejected |

## Rationale

**Why hub-spoke over flat VNet:**
Hub-spoke separates network ownership (hub = platform team, spoke = workload team).
New workloads onboard by peering a new spoke — no changes to existing topology.
Centralised egress through hub enables consistent policy enforcement.

**Why NSGs instead of Firewall in dev:**
Azure Firewall Premium costs ~$2,500/month. In dev, NSG deny-all rules at priority 
4096 provide equivalent east-west segmentation at zero cost. The key risk is no 
deep packet inspection or IDPS — documented accepted risk for non-production.

**Private endpoints for all PaaS:**
Without private endpoints, PaaS services (Key Vault, SQL etc.) resolve to public 
Azure IPs even when accessed from within a VNet. Private endpoints + private DNS 
zones ensure traffic never leaves the Microsoft backbone and public access is 
disabled entirely.

## Consequences
- **Positive:** Zero public IPs on any backend service
- **Positive:** Reusable hub for future workloads
- **Positive:** Private DNS zones ensure correct resolution across all peered VNets
- **Negative:** VNet peering adds latency (~1ms) vs flat VNet
- **Negative:** Azure Firewall cost (~$2,500/mo) deferred to prod
- **Risk:** Dev omits Firewall — no IDPS. Accepted: dev has no real data

## References
- ADR-001: APIM tier (internal VNet mode requirement)
- ADR-004: Authentication strategy
- [Hub-spoke topology](https://learn.microsoft.com/azure/architecture/reference-architectures/hybrid-networking/hub-spoke)
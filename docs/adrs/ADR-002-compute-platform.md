# ADR-002: Compute Platform Selection

**Status:** Accepted  
**Date:** 2026-03-03  
**Deciders:** Lead Azure Architect

## Context
The Order Management API requires a compute platform that supports:
- Zero-downtime deployments (blue-green)
- VNet integration for zero-trust networking (ADR-003)
- Managed Identity for secret-free auth (ADR-004)
- Auto-scale for seasonal traffic spikes
- Minimum operational overhead for a single-service workload

## Decision
**Azure App Service Premium v3 (prod) / Standard S1 (dev)**

## Alternatives Considered

| Option | Monthly Cost | Blue-Green | VNet Integration | Ops Overhead | Decision |
|---|---|---|---|---|---|
| App Service S1 | ~$73/mo | Deployment slots | Full | Low | Accepted (dev) |
| App Service P1v3 | ~$123/mo | Deployment slots | Full + Zone Redundant | Low | Accepted (prod) |
| Azure Container Apps | ~$40/mo | Revisions | Full | Low-Medium | Rejected — see below |
| AKS Standard | ~$200/mo+ | Helm/Argo | Full | High | Rejected — see below |
| Azure Functions | ~$5/mo | Deployment slots | Full | Low | Rejected — see below |

## Rationale

**Why App Service over AKS:**
AKS provides superior flexibility for complex microservice topologies but introduces 
significant operational overhead: cluster upgrades, node pool management, CNI 
configuration, and RBAC complexity. For a single API service, this overhead is 
not justified. ADR documented trade-off: revisit if workload grows beyond 3 services.

**Why App Service over Container Apps:**
Container Apps lacks deployment slots — the atomic swap mechanism is central to 
our zero-downtime deployment strategy. Container Apps uses revision traffic splitting 
which requires more complex pipeline orchestration to achieve equivalent behaviour.

**Why App Service over Functions:**
Order Management API has long-running operations (order processing, bulk queries) 
that exceed the Functions consumption plan timeout. Dedicated App Service plan 
avoids cold starts and timeout constraints.

**Why S1 not B2 for dev:**
Free trial and new Pay-As-You-Go subscriptions restrict Basic tier (quota = 0).
S1 Standard tier is equivalent in capability with identical slot and VNet support.
B2 remains the documented intent for mature paid subscriptions.

## Consequences
- **Positive:** Deployment slots enable atomic blue-green swap with instant rollback
- **Positive:** Zone redundancy in prod (P1v3 × 3 instances across AZs)
- **Positive:** System-assigned MI natively supported — no credential management
- **Negative:** More expensive than Container Apps for low-traffic workloads
- **Negative:** Less portable than containers (tied to App Service runtime)
- **Risk:** Free trial quota restrictions require Pay-As-You-Go upgrade to deploy

## References
- ADR-003: Network Topology (VNet integration requirement)
- ADR-004: Authentication Strategy (Managed Identity requirement)
- [App Service pricing](https://azure.microsoft.com/pricing/details/app-service/linux/)
# ADR-001: APIM Tier Selection

**Status:** Accepted
**Date:** 2026-03-01
**Deciders:** Lead Azure Architect

## Context
The platform requires Azure API Management as the central gateway. APIM has four tiers: Consumption, Developer, Standard, and Premium. The choice directly impacts network isolation capability, SLA, cost, and zero-trust compliance.

## Decision
**Developer tier for dev/test. Premium tier (1 unit) for production.**

## Alternatives Considered

| Tier | Monthly Cost | VNet Mode | SLA | Decision |
|---|---|---|---|---|
| Consumption | ~ (per call) | None | 99.95% | Rejected - no VNet integration |
| Developer | ~ | Internal + External | None | Accepted for dev (no SLA requirement) |
| Standard | ~ | External only | 99.95% | Rejected - external VNet violates zero-trust |
| Premium (1 unit) | ~,800 | Internal + External | 99.95% | Accepted for prod |

## Rationale
Zero-trust requirement mandates that APIM sits inside the VNet with no public IP exposure (internal VNet mode). Only Developer and Premium tiers support internal VNet mode. Developer has no SLA which is acceptable for dev but not prod. Premium adds zone redundancy and multi-region capability aligned to ADR-005 DR strategy.

## Consequences
- **Positive:** Full zero-trust compliance, zone redundancy in prod, multi-region ready
- **Negative:** Premium tier is ,800/month. Mitigated by 1-year Reserved Instance (~40% saving = ~,680/month)
- **Risk:** Developer tier has no SLA. Documented accepted risk for dev environment.

## References
- [APIM pricing](https://azure.microsoft.com/pricing/details/api-management/)
- ADR-003 (Network Topology)

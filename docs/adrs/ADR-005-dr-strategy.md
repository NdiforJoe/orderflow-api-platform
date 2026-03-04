# ADR-005: Disaster Recovery Strategy

**Status:** Accepted  
**Date:** 2026-03-03  
**Deciders:** Lead Azure Architect

## Context
The Order Management API is a revenue-critical system. An outage during peak 
ordering periods (month-end, seasonal spikes) directly impacts business operations.
The platform must define explicit RTO/RPO targets and a cost-justified DR strategy.

Business requirements:
- RTO (Recovery Time Objective): < 1 hour full platform, < 15 min app tier
- RPO (Recovery Point Objective): < 5 minutes for order data
- DR cost must not exceed 30% of primary region cost

## Decision
**Warm standby in paired region (East US 2 → Central US)**

- Azure Front Door Premium as global load balancer and failover controller
- App Service: 0 instances in secondary (scale out to 3 on failover, ~2 min)
- SQL: Active geo-replication with readable secondary (async, < 5s lag)
- Service Bus: Geo-DR metadata sync, manual alias failover
- APIM: Backed up to GRS storage on every deployment, restore on failover (~45 min)
- Redis: Provisioned but empty in secondary (~5 min warm-up from SQL reads)
- Key Vault: Platform-managed geo-redundancy, automatic failover

## Alternatives Considered

| Strategy | RTO | RPO | Monthly Cost | Decision |
|---|---|---|---|---|
| Active-Active (both regions live) | < 1 min | ~0 | +$1,800/mo | Rejected — cost not justified |
| Warm Standby (our choice) | < 15 min app / < 60 min full | < 5 min | +$280/mo | Accepted |
| Cold Standby (IaC redeploy on failure) | 2-4 hours | < 5 min (SQL only) | +$50/mo | Rejected — RTO too high |
| Backup and Restore only | 4-8 hours | Last backup | ~$0 | Rejected — unacceptable RTO |

## Rationale

**Why warm standby over active-active:**
Active-active doubles infrastructure cost (~$1,800/month extra) and introduces 
distributed consistency challenges for the order database. For a single-region 
failure scenario (which covers 99% of real incidents), warm standby achieves 
the required RTO at 25% of the active-active cost.

**Why SQL readable secondary:**
The geo-secondary is not wasted — it serves read-only reporting queries in normal 
operations, partially offsetting the DR cost (~$50/month query value). On failover 
it is promoted to primary via manual CLI command (documented in runbook).

**Why manual failover for Service Bus and SQL (not automatic):**
Automatic failover risks split-brain scenarios where both regions briefly believe 
they are primary. For financial data (orders), a 15-minute manual failover with 
human confirmation is safer than automatic with potential data inconsistency.

**Accepted risks documented:**
- Redis cache loss on failover (~5 min degraded performance, increased SQL load)
- Service Bus in-flight messages may be lost on failover (documented, < 1% of orders)
- APIM restore takes 30-45 min (full platform RTO extended beyond app tier RTO)

## Failover Runbook
See: `/docs/runbooks/dr-failover.md` (created in Phase 5)

Sequence:
- T+0:   Primary failure detected by AFD health probe
- T+2:   AFD shifts traffic to Central US, App Service scales to 3 instances  
- T+15:  SQL manually promoted, Service Bus alias failed over
- T+45:  APIM restored from GRS backup — full platform operational

## Consequences
- **Positive:** RTO < 15 min for app tier (AFD + App Service scale-out)
- **Positive:** RPO < 5 min for order data (SQL async geo-replication)
- **Positive:** SQL readable secondary offsets DR cost
- **Negative:** APIM restore extends full platform RTO to 45 min
- **Negative:** Manual failover steps require trained on-call engineer
- **Risk:** Redis cache warm-up increases SQL load for ~5 min post-failover

## References
- ADR-001: APIM tier (backup/restore capability in Developer and Premium)
- ADR-002: Compute platform (App Service scale-out speed)
- [Azure paired regions](https://learn.microsoft.com/azure/reliability/cross-region-replication-azure)
- [SQL active geo-replication](https://learn.microsoft.com/azure/azure-sql/database/active-geo-replication-overview)
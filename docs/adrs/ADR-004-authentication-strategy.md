# ADR-004: Authentication Strategy

**Status:** Accepted  
**Date:** 2026-03-03  
**Deciders:** Lead Azure Architect

## Context
The platform must authenticate three distinct caller types:
- **B2B partners** — machine-to-machine, no user involved
- **Internal SPA users** — human users via browser
- **Service-to-service** — App Service calling Key Vault, SQL, Redis, Service Bus, ACR

Each caller type has different security requirements. The platform must eliminate
all stored credentials (API keys, connection string passwords, client secrets in
config files) — a primary driver from the legacy system's ISO 27001 gaps.

## Decision
**Entra ID for all external auth. Managed Identity for all service-to-service auth.**

- B2B partners: OAuth 2.0 client credentials flow
- SPA users: OAuth 2.0 auth code + PKCE flow
- Service-to-service: System-assigned Managed Identity + RBAC
- APIM validates all JWTs — backend never sees raw tokens

## Alternatives Considered

| Approach | Stored Secrets | MFA Support | Audit Trail | Decision |
|---|---|---|---|---|
| API keys per consumer | Yes — in config files | No | Partial | Rejected — existing problem |
| Client secrets in App Settings | Yes — rotated manually | No | Partial | Rejected — manual rotation risk |
| Managed Identity everywhere | No | N/A | Full via Entra logs | Accepted for service-to-service |
| Entra ID client credentials | No (cert or MI) | No (machine) | Full | Accepted for B2B |
| Entra ID auth code + PKCE | No | Yes | Full | Accepted for SPA users |
| Certificate-based auth | Cert management overhead | No | Full | Rejected — complexity without benefit |

## Rationale

**Why Managed Identity over client secrets for service-to-service:**
Managed Identity is issued and rotated by Azure automatically — there is no
secret to store, rotate, or accidentally commit to a repository. The App Service
MI gets precisely scoped RBAC roles (Key Vault Secrets User, AcrPull,
Service Bus Data Sender) — least privilege enforced in Bicep, not manually.

**Why client credentials for B2B over API keys:**
API keys are static, have no expiry by default, and cannot be scoped to specific
operations. Client credentials flow issues short-lived JWTs (1hr default) that
APIM validates on every request. Compromise of a client secret can be remediated
by rotating it in Entra ID without touching any platform configuration.

**Why auth code + PKCE for SPA over implicit flow:**
Implicit flow is deprecated by OAuth 2.0 Security BCP. PKCE prevents
authorization code interception attacks — critical for browser-based clients
where the client secret cannot be kept confidential.

**Why APIM strips the JWT before forwarding to backend:**
The backend should never make auth decisions — that is APIM's job. Stripping
the JWT and replacing it with trusted enriched headers (X-Consumer-Id,
X-Tenant-Id, X-Consumer-Scope) means backend code cannot accidentally
bypass gateway policy by reading the raw token.

## Consequences
- **Positive:** Zero stored credentials anywhere in the platform
- **Positive:** All auth decisions at single enforcement point (APIM)
- **Positive:** Entra ID audit logs provide full caller identity trail
- **Positive:** MI rotation is automatic — no operational overhead
- **Negative:** Entra ID app registrations must be created and maintained
- **Negative:** Client credentials flow requires partners to manage their own secret rotation
- **Risk:** MI compromise = broad access — mitigated by least-privilege RBAC scoping

## References
- ADR-001: APIM tier (JWT validation capability)
- ADR-003: Network topology (APIM as single entry point)
- [OAuth 2.0 Security BCP](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-security-topics)
- [Managed Identity overview](https://learn.microsoft.com/azure/active-directory/managed-identities-azure-resources/overview)
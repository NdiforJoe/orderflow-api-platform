# Screenshot Capture Guide
# OrderFlow API Platform — Phase by Phase

Save this file. Follow it each phase immediately after deployment while portal is fresh.
All screenshots go in: docs/screenshots/
Naming convention: phase{N}-{NN}-{description}.png

==============================================================================
PHASE 2 — NETWORKING AND KEY VAULT
==============================================================================

HOW TO CAPTURE ON WINDOWS:
  Windows + Shift + S  →  crop tightly  →  save as PNG
  Tip: hide the browser bookmarks bar first (Ctrl+Shift+B to toggle)
  Tip: maximise the browser window before capturing

------------------------------------------------------------------------------
Screenshot 1 of 6
File:     docs/screenshots/phase2-01-deployment-succeeded.png
Label:    "Deployment Succeeded — 20+ resources provisioned via single Bicep command"

Portal path:
  portal.azure.com
  → Subscriptions
  → Azure subscription 1
  → Deployments  (left sidebar)
  → Click the row: deploy-orderflow-dev-20260301-2156

Capture: The deployment detail page showing:
  ✓ Status: Succeeded  (green tick)
  ✓ Deployment name visible
  ✓ Duration visible
  ✓ Resource count visible

Why this matters for your post:
  Proves you executed real IaC, not just wrote YAML.
  "Single command, 20+ resources, 5 minutes" is a strong talking point.

------------------------------------------------------------------------------
Screenshot 2 of 6
File:     docs/screenshots/phase2-02-vnet-peering-connected.png
Label:    "Hub-Spoke VNet Peering — Connected + FullyInSync (ADR-003 Zero-Trust)"

Portal path:
  portal.azure.com
  → Resource groups
  → rg-orderflow-network-dev
  → vnet-hub-dev
  → Peerings  (left sidebar under Settings)

Capture: The peerings list showing:
  ✓ peer-hub-to-spoke listed
  ✓ Peering status: Connected  (green)
  ✓ Sync status: FullyInSync
  ✓ Allow gateway transit column visible

Why this matters for your post:
  Hub-spoke is the enterprise network pattern. "Connected + FullyInSync"
  proves the topology works, not just that the config was accepted.
  Directly maps to ADR-003 in your repo.

------------------------------------------------------------------------------
Screenshot 3 of 6
File:     docs/screenshots/phase2-03-keyvault-networking.png
Label:    "Key Vault — Public Access Disabled + Private Endpoint Only (Zero-Trust)"

Portal path:
  portal.azure.com
  → Resource groups
  → rg-orderflow-dev
  → kv-orderflow-dev-dev001
  → Networking  (left sidebar under Settings)

Capture: The networking tab showing:
  ✓ "Public network access: Disabled"  — this is the key detail
  ✓ Private endpoint connections section showing pe-kv-orderflow-dev
  ✓ Status: Approved

Annotation tip:
  Use Windows Snip & Sketch pen tool to draw a red circle or arrow
  pointing to "Public network access: Disabled"
  This one annotation tells the whole zero-trust story instantly.

Why this matters for your post:
  This is the most visually impactful screenshot of Phase 2.
  A Key Vault that literally cannot be reached from the internet,
  not even by someone with the right credentials and the right IP.
  Only accessible via private endpoint inside the VNet.

------------------------------------------------------------------------------
Screenshot 4 of 6
File:     docs/screenshots/phase2-04-private-dns-zones.png
Label:    "5 Private DNS Zones — All PaaS services resolve to private IPs"

Portal path:
  portal.azure.com
  → Resource groups
  → rg-orderflow-network-dev
  → Filter by type: Private DNS zone  (use the Type filter dropdown)

Capture: The resource list filtered to show all 5 zones:
  ✓ privatelink.vaultcore.azure.net
  ✓ privatelink.database.windows.net
  ✓ privatelink.servicebus.windows.net
  ✓ privatelink.redis.cache.windows.net
  ✓ privatelink.azurecr.io

Why this matters for your post:
  Most people know what private endpoints are but don't know that
  without DNS zones the private endpoint does nothing — services still
  resolve to public IPs. This screenshot shows you understand the full
  picture, not just the checkbox.

------------------------------------------------------------------------------
Screenshot 5 of 6
File:     docs/screenshots/phase2-05-vscode-bicep.png
Label:    "Infrastructure as Code — NSG deny-all rule in networking.bicep (ADR-003)"

How to capture:
  Switch to VS Code
  Open: infra\bicep\modules\networking.bicep
  Scroll to the dataNsg resource (around line 80)
  Make sure the Deny-All-Inbound rule block is visible:

    {
      name: 'Deny-All-Inbound'
      properties: {
        priority: 4096
        protocol: '*'
        access: 'Deny'
        ...

  Use a dark theme (e.g. One Dark Pro) for best visual contrast
  Zoom in to font size 14+ so code is readable in screenshot

Why this matters for your post:
  Shows the security decision is in code, not in someone's head.
  The deny-all at priority 4096 is a deliberate architectural choice —
  having it in Bicep means it survives any redeployment.
  This is what "GitOps" and "policy as code" look like in practice.

------------------------------------------------------------------------------
Screenshot 6 of 6
File:     docs/screenshots/phase2-06-github-repo.png
Label:    "Repository Structure — Architecture as Code, not Architecture as PowerPoint"

How to capture:
  Open browser
  Go to: github.com/YOUR-USERNAME/orderflow-api-platform
  Make sure you can see:
    ✓ /infra/bicep folder
    ✓ /docs/adrs folder
    ✓ /src folder
    ✓ README.md with badges rendering
    ✓ Most recent commit message visible

Why this matters for your post:
  Recruiters and hiring managers will click your GitHub link.
  This is the first thing they see. Clean structure, real commits,
  ADRs in /docs/adrs — this is what separates a portfolio project
  from a "I followed a tutorial" repo.

==============================================================================
AFTER CAPTURING ALL 6 SCREENSHOTS
==============================================================================

1. Rename all files exactly as shown above (case sensitive, hyphens not spaces)

2. Save them to: docs/screenshots/ in your repo

3. Commit and push:

   git add docs/screenshots/
   git commit -m "docs: add Phase 2 deployment screenshots

   - Deployment succeeded (deploy-orderflow-dev-20260301-2156)
   - VNet peering Connected + FullyInSync
   - Key Vault public access disabled (zero-trust proof)
   - 5 private DNS zones deployed
   - networking.bicep deny-all NSG rule
   - GitHub repo structure"

   git push origin main

4. Verify the screenshots render in README.md:
   Go to github.com/YOUR-USERNAME/orderflow-api-platform
   README should display all 6 screenshots inline
   If any show as broken links, check the filename matches exactly

==============================================================================
PHASE 3 SCREENSHOTS (capture after Phase 3 deployment)
==============================================================================

phase3-01-log-analytics-workspace.png
  Path: rg-orderflow-dev → log-orderflow-dev → Overview
  Shows: Workspace ID, retention days, daily cap

phase3-02-app-insights-live-metrics.png
  Path: rg-orderflow-dev → appi-orderflow-dev → Live Metrics
  Shows: Live request stream (trigger a few test requests first)

phase3-03-kql-alert-rules.png
  Path: rg-orderflow-dev → Monitor → Alerts → Alert rules
  Shows: All 4 custom KQL alert rules listed

phase3-04-app-service-vnet-integration.png
  Path: rg-orderflow-dev → app-orderflow-dev → Networking
  Shows: VNet integration enabled, subnet snet-app, route all traffic ON

phase3-05-app-service-managed-identity.png
  Path: rg-orderflow-dev → app-orderflow-dev → Identity
  Shows: System assigned MI, Status: On, Object ID visible

==============================================================================
PHASE 4 SCREENSHOTS (capture after Phase 4 deployment)
==============================================================================

phase4-01-apim-overview.png
  Path: rg-orderflow-dev → apim-orderflow-dev → Overview
  Shows: Developer tier, internal VNet mode, no public IP

phase4-02-apim-policy-jwt-validate.png
  Path: apim-orderflow-dev → APIs → Order API → All operations → Policy editor
  Shows: validate-jwt policy XML visible in editor

phase4-03-apim-products.png
  Path: apim-orderflow-dev → Products
  Shows: Internal and Partner products listed

phase4-04-apim-virtual-network.png
  Path: apim-orderflow-dev → Network → Virtual network
  Shows: Internal mode, VNet and subnet listed

==============================================================================
PHASE 5 SCREENSHOTS (capture after Phase 5 deployment)
==============================================================================

phase5-01-app-running-health-check.png
  URL: https://apim-orderflow-dev.azure-api.net/orders/health
  Shows: {"status":"healthy"} response in browser

phase5-02-app-insights-request-trace.png
  Path: appi-orderflow-dev → Transaction search → pick a request
  Shows: End-to-end trace with correlation ID, dependency calls

phase5-03-sql-private-endpoint.png
  Path: rg-orderflow-dev → sql-orderflow-dev → Networking
  Shows: Public endpoint disabled, private endpoint listed

==============================================================================
PHASE 6 SCREENSHOTS (capture after Phase 6 pipeline runs)
==============================================================================

phase6-01-github-actions-all-gates-green.png
  Path: github.com → Actions → latest CD run
  Shows: All 5 stages green (Build, Security Gates, Dev Deploy, DAST, Prod Deploy)

phase6-02-security-gates-detail.png
  Path: GitHub Actions → Security Gates job → expand steps
  Shows: CodeQL, Snyk, Trivy all passed

phase6-03-blue-green-slot-swap.png
  Path: rg-orderflow-dev → app-orderflow-dev → Deployment slots
  Shows: Production and staging slots, swap history

==============================================================================
ANNOTATION GUIDE (optional but recommended for LinkedIn carousel)
==============================================================================

Tools (free):
  - Windows Snip & Sketch built-in pen: red circles/arrows
  - Canva (canva.com): add text labels, consistent styling
  - PowerPoint: insert screenshot, add text boxes

Annotation style to use:
  - Red circle or arrow pointing to the key detail
  - One short text label max (e.g. "Public access: DISABLED")
  - Keep annotations minimal — let the screenshot speak

For LinkedIn carousel (6-8 slides):
  Slide 1:  Architecture diagram (diagram1-network-topology.png exported from Draw.io)
  Slide 2:  phase2-01-deployment-succeeded.png
  Slide 3:  phase2-02-vnet-peering-connected.png  (annotated)
  Slide 4:  phase2-03-keyvault-networking.png  (annotated — red circle on Disabled)
  Slide 5:  phase2-04-private-dns-zones.png
  Slide 6:  phase2-05-vscode-bicep.png
  Slide 7:  phase2-06-github-repo.png
  Slide 8:  Text slide: "Full repo + 6 ADRs in comments"

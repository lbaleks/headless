# Copilot Instructions for Litebrygg M2 Codebase

## Overview
This monorepo manages integrations and admin tools for a Magento 2 (M2) e-commerce backend. It includes:
- **admstage/**: Next.js admin dashboard (TypeScript, React)
- **m2-gateway/**: Node.js/Express API gateway for Magento 2
- **apps/api/**: Fastify-based API (experimental/utility)
- Numerous shell scripts for patching, syncing, and automating M2 workflows

## Key Workflows
- **Gateway/Backend**: Start with `node m2-gateway/api/src/server.js` (or use provided scripts)
- **Admin UI**: Start with `npm run dev` in `admstage/` (Next.js, port 3000)
- **Variant Module**: Install via `install-variant-module.sh` (creates admin UI page and gateway route)
- **Shell Automation**: Scripts (e.g., `fix-*`, `install-*`, `patch-*`) automate Magento data/model fixes and syncs. Many expect environment variables and direct file edits.

## Conventions & Patterns
- **API Gateway**: All Magento API calls proxy through `m2-gateway`, using environment variables for credentials (`MAGENTO_BASE`, `MAGENTO_TOKEN`).
- **Admin UI**: Uses `/lib/api.ts` for gateway communication. Pages are in `/app/`, with feature modules under `/app/m2/`.
- **Shell Scripts**: Use `set -euo pipefail` for safety. Many scripts patch JS files or generate TypeScript/React pages dynamically.
- **Idempotency**: Most backend and shell operations are designed to be safely re-run.
- **Error Handling**: Gateway endpoints return `{ ok: true/false, error }` JSON. Admin UI displays errors in `<pre>` blocks.

## Integration Points
- **Magento 2**: All product/category/variant operations go through REST endpoints, with custom logic for healing, syncing, and patching.
- **Variant Healing**: `/ops/variant/heal` endpoint (gateway) and `/m2/variants` page (admin) are tightly coupled. See `install-variant-module.sh` for setup.
- **Category Sync/Replace**: `/ops/category/replace` endpoint for bulk category updates.

## Examples
- **Add Variant**: Use `/m2/variants` admin page, which POSTs to `/ops/variant/heal` via gateway.
- **Health Check**: `/health/magento` endpoint verifies gateway-Magento connectivity.
- **Scripted Patch**: Run e.g. `fix-admin-ui-safe.sh` to patch admin UI files or data.

## Tips for AI Agents
- Always check for required environment variables before running backend/gateway code.
- When adding new admin features, place pages in `admstage/app/m2/` and use `/lib/api.ts` for backend calls.
- For new gateway endpoints, add routes in `m2-gateway/routes-*.js` and register in `server.js`.
- Use shell scripts for bulk operations and automation—review their logic for conventions.
- Maintain idempotency and clear error reporting in all new endpoints and scripts.

## References
- `admstage/README.md`: Next.js admin setup
- `install-variant-module.sh`: Example of cross-component automation
- `m2-gateway/api/src/server.js`: Gateway endpoint patterns
- `admstage/lib/api.ts`: Admin UI API conventions

---
*Update this file as workflows or conventions evolve. Ask for clarification if any pattern is unclear or undocumented.*

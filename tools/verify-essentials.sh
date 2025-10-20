#!/usr/bin/env bash
set -euo pipefail
BASE=${BASE:-http://localhost:3000}
say(){ printf "%s\n" "$*"; }
say "→ Health";           curl -fsS "$BASE/api/debug/health" | jq '.ok'
say "→ Single completeness"; curl -fsS "$BASE/api/products/completeness?sku=TEST" | jq '{sku:(.items[0].sku),family:(.items[0].family),score:(.items[0].completeness.score)}'
say "→ Attributes";       curl -fsS "$BASE/api/products/attributes/TEST" | jq .

#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$HOME/Documents/M2}"
GW_DIR="${GATEWAY_DIR:-$ROOT/m2-gateway}"
SERVER="$GW_DIR/server.js"
ROUTE="$GW_DIR/routes-categories.js"

[ -d "$GW_DIR" ] || { echo "❌ Fant ikke m2-gateway i $GW_DIR"; exit 1; }
[ -f "$SERVER" ] || { echo "❌ Fant ikke server.js i $GW_DIR"; exit 1; }

# 1) Skriv rute for kategori-replace (idempotent)
cat > "$ROUTE" <<'JS'
const express = require('express');
const router = express.Router();
const fetch = (...args) => import('node-fetch').then(({default: f}) => f(...args));

function cfg() {
  const base = process.env.MAGENTO_BASE?.replace(/\/+$/,'');
  let tok = process.env.MAGENTO_TOKEN || process.env.M2_ADMIN_TOKEN || '';
  if (tok && !/^Bearer\s/i.test(tok)) tok = 'Bearer ' + tok;
  return { base, tok };
}

async function putProductCategories(base, tok, sku, ids) {
  const body = {
    product: {
      sku,
      extension_attributes: {
        category_links: ids.map(id => ({ position: 0, category_id: String(id) }))
      }
    }
  };
  const res = await fetch(`${base}/rest/V1/products/${encodeURIComponent(sku)}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json', 'Authorization': tok },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const t = await res.text().catch(()=> '');
    throw new Error(t || `PUT failed (${res.status})`);
  }
  return res.json();
}

/**
 * POST /ops/category/replace
 * { items: [ { sku: "SKU", categoryIds: [2,5,7] }, ... ] }
 */
router.post('/ops/category/replace', async (req, res) => {
  try {
    const { base, tok } = cfg();
    if (!base || !tok) return res.status(500).json({ ok:false, error:"MAGENTO_BASE/TOKEN mangler" });

    const items = Array.isArray(req.body?.items) ? req.body.items : [];
    const out = [];
    for (const it of items) {
      const sku = String(it.sku || '').trim();
      const ids = (Array.isArray(it.categoryIds) ? it.categoryIds : [])
        .map(n => Number(n)).filter(n => Number.isFinite(n));
      if (!sku || ids.length === 0) {
        out.push({ sku, ok:false, error:"Ugyldig input" });
        continue;
      }
      await putProductCategories(base, tok, sku, ids);
      out.push({ sku, ok:true, categoryIds: ids });
    }
    res.json({ ok:true, items: out });
  } catch (e) {
    res.status(500).json({ ok:false, error: String(e.message || e) });
  }
});

module.exports = (app) => app.use(router);
JS

echo "✅ Skrev $ROUTE"

# 2) Wire ruten inn i server.js (før app.listen)
if ! grep -q "routes-categories" "$SERVER"; then
  cp "$SERVER" "$SERVER.bak.$(date +%s)"
  # Sett inn rett før app.listen(
  perl -0777 -pe 's|(app\.use\(express\.json\(\)\);\s*)|\1\n// Categories routes\nrequire("./routes-categories")(app);\n|s' -i "$SERVER"
  # Hvis den linja ikke fantes, prøv før "app.listen"
  if ! grep -q "routes-categories" "$SERVER"; then
    perl -0777 -pe 's|(app\.listen\()|// Categories routes\nrequire("./routes-categories")(app);\n\n$1|s' -i "$SERVER"
  fi
  echo "✅ Patcha server.js (require('./routes-categories')(app))"
else
  echo "ℹ️  server.js har allerede routes-categories."
fi

# 3) Restart-hint + sanity curl
PORT="${PORT:-$(grep -E '^PORT=' "$GW_DIR/.env" 2>/dev/null | cut -d= -f2 || echo 3044)}"
echo "🚀 Restart gateway og test:"
echo "   (cd \"$GW_DIR\" && pkill -f 'node server.js' 2>/dev/null || true; node server.js & sleep 1)"
echo "   curl -sS http://localhost:${PORT}/ops/category/replace -X POST -H 'Content-Type: application/json' \\"
echo "     -d '{\"items\":[{\"sku\":\"TEST-RED\",\"categoryIds\":[2,4]}]}' | jq"

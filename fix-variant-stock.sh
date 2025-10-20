#!/usr/bin/env bash
set -euo pipefail

# Finn m2-gateway
GATEWAY_DIR="$(find "$HOME/Documents/M2" -type d -name m2-gateway | head -n1)"
[ -d "$GATEWAY_DIR" ] || { echo "❌ Fant ikke m2-gateway"; exit 1; }

FILE="$GATEWAY_DIR/routes-variants.js"
[ -f "$FILE" ] || { echo "❌ Fant ikke $FILE"; exit 1; }

# Backup
cp -v "$FILE" "$FILE.bak.$(date +%Y%m%d-%H%M%S)"

# Patching via Node (mer robust enn sed/perl på tvers av små forskjeller)
node - <<'NODE'
const fs = require('fs');
const path = require('path');

const gw = process.env.GATEWAY_DIR || '';
const file = process.env.FILE || '';
if (!file) { console.error('Missing FILE env'); process.exit(1); }

let s = fs.readFileSync(file, 'utf8');

// 1) Ny, robust upsertStock (MSI wrapper -> MSI raw -> legacy). Tillater passering ved FORBIDDEN hvis env ber om det.
const newUpsert = `
async function upsertStock({ sku, source_code, quantity, status }) {
  const j = (x) => JSON.stringify(x);

  // --- MSI (Inventory) først: wrapper-shape ---
  let r = await mfetch(\`/rest/V1/inventory/source-items\`, {
    method: "POST",
    body: j({ sourceItems: [{ sku, source_code, quantity, status }] }),
  });
  if (r.ok) return true;

  // Noen miljøer krever rå array
  if (r.status === 400 || r.status === 415) {
    const r2 = await mfetch(\`/rest/V1/inventory/source-items\`, {
      method: "POST",
      body: j([{ sku, source_code, quantity, status }]),
    });
    if (r2.ok) return true;
    r = r2; // ta vare på siste svar
  }

  // --- Legacy fallback ---
  if (r.status === 404 || r.status === 400) {
    const legacy = await mfetch(
      \`/rest/V1/products/\${encodeURIComponent(sku)}/stockItems/1\`,
      {
        method: "PUT",
        body: j({
          stockItem: {
            qty: Number(quantity || 0),
            is_in_stock: Number(status || 1) === 1 ? 1 : 0,
          },
        }),
      }
    );

    if (
      legacy.ok ||
      process.env.VARIANT_FORCE_SKIP_STOCK === "1" ||
      process.env.VARIANT_ALLOW_STOCK_FORBIDDEN === "1"
    ) {
      return true;
    }

    throw new Error(\`Legacy stock update failed: \${JSON.stringify(legacy.data)}\`);
  }

  throw new Error(\`Stock update failed: \${JSON.stringify(r.data)}\`);
}
`.trim() + "\n";

// 2) Erstatt eksisterende upsertStock-blokk om den finnes, ellers sett inn like over export/route.
if (/async\s+function\s+upsertStock\s*\(/.test(s)) {
  s = s.replace(/async\s+function\s+upsertStock[\s\S]*?\n}\s*\n/, newUpsert);
} else {
  // Sett inn før første "module.exports" eller "app.use("/ops/variant","
  const insPts = [
    s.indexOf('module.exports'),
    s.indexOf('export default'),
    s.indexOf('app.use("/ops/variant"'),
  ].filter(i => i >= 0);
  const idx = insPts.length ? Math.min(...insPts) : s.length;
  s = s.slice(0, idx) + "\n" + newUpsert + "\n" + s.slice(idx);
}

// 3) Sørg for at heal-koden sender inn sku eksplisitt: upsertStock({ sku, ...stock })
s = s.replace(/await\s+upsertStock\s*\(\s*stock\s*\)/g, 'await upsertStock({ sku, ...stock })');
// også vanlige varianter med if (stock)
s = s.replace(/if\s*\(\s*stock\s*\)\s*await\s+upsertStock\s*\(\s*stock\s*\)\s*;/g, 'if (stock) await upsertStock({ sku, ...stock });');

fs.writeFileSync(file, s, 'utf8');
console.log('✅ Patchet routes-variants.js (robust upsertStock + korrekt sku til legacy)');
NODE

# Restart gateway i forgrunnen (viser ev. feil tydelig)
pkill -f "$GATEWAY_DIR/server.js" 2>/dev/null || true
node "$GATEWAY_DIR/server.js" &
sleep 1

echo "➡️  Sanity:"
curl -sS http://localhost:3044/health/magento | jq || true
echo
echo "➡️  Test heal (med stock):"
curl -sS -X POST http://localhost:3044/ops/variant/heal \
  -H 'Content-Type: application/json' \
  -d '{"parentSku":"TEST-CFG","sku":"TEST-BLUE-EXTRA","cfgAttr":"cfg_color","cfgValue":7,"label":"Blue","websiteId":1,"stock":{"source_code":"default","quantity":5,"status":1}}' | jq || true

#!/usr/bin/env bash
set -euo pipefail

# Finn m2-gateway
GATEWAY_DIR="$(find "$HOME/Documents/M2" -type d -name m2-gateway | head -n1)"
[ -d "$GATEWAY_DIR" ] || { echo "❌ Fant ikke m2-gateway"; exit 1; }

FILE="$GATEWAY_DIR/routes-variants.js"
[ -f "$FILE" ] || { echo "❌ Fant ikke $FILE"; exit 1; }

# Backup
cp -v "$FILE" "$FILE.bak.$(date +%Y%m%d-%H%M%S)"

# === Patch via Node (passer FILE i env!) ===
FILE="$FILE" node - <<'NODE'
const fs = require('fs');
const file = process.env.FILE;
if (!file) { console.error('Missing FILE env'); process.exit(1); }

let s = fs.readFileSync(file, 'utf8');

// Robust upsertStock (MSI wrapper -> MSI raw -> legacy) + skip når env ber om det
const newUpsert =
`async function upsertStock({ sku, source_code, quantity, status }) {
  const j = (x) => JSON.stringify(x);

  // 1) MSI wrapper-shape
  let r = await mfetch(\`/rest/V1/inventory/source-items\`, {
    method: "POST",
    body: j({ sourceItems: [{ sku, source_code, quantity, status }] }),
  });
  if (r.ok) return true;

  // 2) MSI raw array
  if (r.status === 400 || r.status === 415) {
    const r2 = await mfetch(\`/rest/V1/inventory/source-items\`, {
      method: "POST",
      body: j([{ sku, source_code, quantity, status }]),
    });
    if (r2.ok) return true;
    r = r2; // behold siste feilsvar
  }

  // 3) Legacy fallback
  if (r.status === 404 || r.status === 400) {
    const legacy = await mfetch(\`/rest/V1/products/\${encodeURIComponent(sku)}/stockItems/1\`, {
      method: "PUT",
      body: j({
        stockItem: {
          qty: Number(quantity || 0),
          is_in_stock: Number(status || 1) === 1 ? 1 : 0,
        },
      }),
    });

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
`;

// Bytt ut eksisterende upsertStock, evt. sett inn
if (/async\s+function\s+upsertStock\s*\(/.test(s)) {
  s = s.replace(/async\s+function\s+upsertStock[\s\S]*?\n}\s*\n/, newUpsert + "\n");
} else {
  const idx =
    [s.indexOf('module.exports'), s.indexOf('export default'), s.indexOf('app.use("/ops/variant"')]
      .filter(i => i >= 0).sort((a,b)=>a-b)[0] ?? s.length;
  s = s.slice(0, idx) + "\n" + newUpsert + "\n" + s.slice(idx);
}

// Sørg for at vi sender med sku inn i upsertStock-kallet
s = s.replace(/await\s+upsertStock\s*\(\s*stock\s*\)/g, 'await upsertStock({ sku, ...stock })');
s = s.replace(/if\s*\(\s*stock\s*\)\s*await\s+upsertStock\s*\(\s*stock\s*\)\s*;/g,
              'if (stock) await upsertStock({ sku, ...stock });');

fs.writeFileSync(file, s, 'utf8');
console.log('✅ Patchet routes-variants.js (robust upsertStock + korrekt sku i legacy-kall)');
NODE

# Restart gateway og test
pkill -f "$GATEWAY_DIR/server.js" 2>/dev/null || true
node "$GATEWAY_DIR/server.js" & sleep 1

echo "➡️  Sanity:"
curl -sS http://localhost:3044/health/magento | jq || true
echo
echo "➡️  Test heal (med stock):"
curl -sS -X POST http://localhost:3044/ops/variant/heal \
  -H 'Content-Type: application/json' \
  -d '{"parentSku":"TEST-CFG","sku":"TEST-BLUE-EXTRA","cfgAttr":"cfg_color","cfgValue":7,"label":"Blue","websiteId":1,"stock":{"source_code":"default","quantity":5,"status":1}}' | jq || true

#!/usr/bin/env bash
set -euo pipefail
f="routes-variants.js"
[ -f "$f" ] || { echo "❌ Fant ikke $f"; exit 1; }

# Backup først
cp -a "$f" "$f.bak.$(date +%s)"

# Erstatt HELE upsertStock-funksjonen med en robust versjon.
# Matcher fra "const upsertStock = async (" til første påfølgende linje som slutter med "};"
perl -0777 -pe '
  s|const\s+upsertStock\s*=\s*async\s*\(\{.*?\n\};|const upsertStock = async ({ sku, source_code, quantity, status }) => {
  const q = Number(quantity || 0);
  const s = Number(status || 1);

  // Try #1: MSI wrapper-shape
  let r = await mfetch("/rest/V1/inventory/source-items", {
    method: "POST",
    body: j({ sourceItems: [{ sku, source_code, quantity: q, status: s }] })
  });
  if (r.ok) return true;

  // Try #2: MSI raw array hvis feilen referer til "sourceItems"
  const msg = (r.data && (r.data.message || r.data)) || "";
  if (Number(r.status || 0) === 400 && String(msg).toLowerCase().includes("sourceitems")) {
    const r2 = await mfetch("/rest/V1/inventory/source-items", {
      method: "POST",
      body: j([{ sku, source_code, quantity: q, status: s }])
    });
    if (r2.ok) return true;
    r = r2;
  }

  // Try #3: Legacy stock (fallback ved 400/401/403/404 fra MSI)
  if ([400, 401, 403, 404].includes(Number(r.status || 0))) {
    const legacy = await mfetch(`/rest/V1/products/${encodeURIComponent(sku)}/stockItems/1`, {
      method: "PUT",
      body: j({ stockItem: { qty: q, is_in_stock: s === 1 ? 1 : 0 } })
    });
    if (legacy.ok) return true;
    throw new Error("Legacy stock update failed: " + JSON.stringify(legacy.data));
  }

  // Ellers: rapporter MSI-feilen
  throw new Error("Stock update failed: " + JSON.stringify(r.data));
};|s
' -i "$f"

echo "✅ Patchet $f (robust MSI→legacy fallback)."

# Rask syntakssjekk – Node prøver å parse fila
node -e "require('./routes-variants.js'); console.log('✅ Syntax OK')"

# Restart gateway stille
pkill -f "node server.js" 2>/dev/null || true
node server.js >/dev/null 2>&1 & sleep 1

# Sanity
curl -sS http://localhost:3044/health/magento | jq -r '.ok' >/dev/null && echo "✅ Gateway OK" || echo "❌ Gateway feilet"

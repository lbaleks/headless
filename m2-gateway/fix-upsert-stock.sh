#!/usr/bin/env bash
set -euo pipefail
f="routes-variants.js"
[ -f "$f" ] || { echo "❌ Fant ikke $f"; exit 1; }
cp -a "$f" "$f.bak.$(date +%s)"

awk '
BEGIN{out=1}
/const upsertStock = async \(\{/{
  out=0
  print "const upsertStock = async ({ sku, source_code, quantity, status }) => {"
  print "  const q = Number(quantity||0);"
  print "  const s = Number(status||1);"
  print "  const wrapper = { sourceItems: [{ sku, source_code, quantity: q, status: s }] };"
  print "  const rawArr  = [{ sku, source_code, quantity: q, status: s }];"
  print ""
  print "  // Try #1: MSI wrapper-shape"
  print "  let r = await mfetch(\"/rest/V1/inventory/source-items\", { method: \"POST\", body: j(wrapper) });"
  print "  if (r.ok) return true;"
  print ""
  print "  // If Magento klager på missing sourceItems → prøv raw array"
  print "  const msg = (r.data && (r.data.message || r.data)) || \"\";"
  print "  if (r.status === 400 && /sourceItems/i.test(String(msg))) {"
  print "    const r2 = await mfetch(\"/rest/V1/inventory/source-items\", { method: \"POST\", body: j(rawArr) });"
  print "    if (r2.ok) return true;"
  print "  }"
  print ""
  print "  // Try #2: Legacy stock API som fallback"
  print "  if (r.status === 404 || r.status === 400) {"
  print "    const legacy = await mfetch(\"/rest/V1/products/\" + encodeURIComponent(sku) + \"/stockItems/1\", {"
  print "      method: \"PUT\","
  print "      body: j({ stockItem: { qty: q, is_in_stock: s === 1 ? 1 : 0 } })"
  print "    });"
  print "    if (legacy.ok) return true;"
  print "    throw new Error(\"Legacy stock update failed: \" + JSON.stringify(legacy.data));"
  print "  }"
  print ""
  print "  throw new Error(\"Stock update failed: \" + JSON.stringify(r.data));"
  print "};"
  next
}
out==1{ print }
' "$f" > "$f.tmp"

mv "$f.tmp" "$f"
echo "✅ Patched $f"

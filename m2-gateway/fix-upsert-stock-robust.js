const fs = require("fs");
const f = "routes-variants.js";
if (!fs.existsSync(f)) { console.error("❌ Fant ikke", f); process.exit(1); }
const src = fs.readFileSync(f, "utf8");

const replacement = `const upsertStock = async ({ sku, source_code, quantity, status }) => {
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
    r = r2; // ta vare på sist svar
  }

  // Try #3: Legacy stock (fallback ved 400/401/403/404 fra MSI)
  if ([400,401,403,404].includes(Number(r.status || 0))) {
    const legacy = await mfetch(\`/rest/V1/products/\${encodeURIComponent(sku)}/stockItems/1\`, {
      method: "PUT",
      body: j({ stockItem: { qty: q, is_in_stock: s === 1 ? 1 : 0 } })
    });
    if (legacy.ok) return true;
    throw new Error("Legacy stock update failed: " + JSON.stringify(legacy.data));
  }

  // Ellers: rapporter MSI-feilen
  throw new Error("Stock update failed: " + JSON.stringify(r.data));
};`;

const re = /const\s+upsertStock\s*=\s*async\s*\([^)]*\)\s*=>\s*\{[\s\S]*?\n\};/m;
if (!re.test(src)) { console.error("❌ Fant ikke eksisterende upsertStock() å erstatte."); process.exit(1); }
fs.writeFileSync(f + ".bak", src);
fs.writeFileSync(f, src.replace(re, replacement));
console.log("✅ Patchet", f, "(robust MSI→legacy fallback).");

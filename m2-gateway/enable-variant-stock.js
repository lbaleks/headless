const fs = require('fs');
const path = require('path');

const file = path.resolve('./routes-variants.js');
if (!fs.existsSync(file)) {
  console.error('Fant ikke routes-variants.js');
  process.exit(1);
}
const src = fs.readFileSync(file, 'utf8');

// 1) Ikke la env-flagget stoppe stock
let out = src
  .replace(/const\s+forceSkip\s*=\s*process\.env\.VARIANT_FORCE_SKIP_STOCK[^\n]*;/,
           'const forceSkip = false; // patched: always allow stock');

// 2) Tving heal til å kjøre upsertStock når body.stock finnes
//  – vi treffer et vanlig mønster: if (body.stock && !forceSkip) await upsertStock(...)
//  – hvis (!forceSkip) mangler, så legger vi det inn; hvis hele kallet mangler, injiserer vi et
//    try/catch-kall rett før retur.
if (!/upsertStock\s*\(/.test(out)) {
  // Legg inn en minimal upsertStock hvis den ikke finnes (sikkerhetsnett)
  out = out.replace(/module\.exports\s*=\s*\(app\)\s*=>\s*\{/,
`const upsertStock = async (sku, stock) => {
  // MSI wrapper med raw array (Magento svarer [] ved OK)
  const body = Array.isArray(stock) ? stock : [{ sku, ...stock }];
  const r = await mfetch('/rest/V1/inventory/source-items', { method:'POST', body: j({ sourceItems: body }) });
  if (r.ok) return true;
  // fallback: noen miljøer vil ha rå array
  const r2 = await mfetch('/rest/V1/inventory/source-items', { method:'POST', body: j(body) });
  if (r2.ok) return true;
  // legacy (krever sku riktig i path!)
  const legacy = await mfetch(\`/rest/V1/products/\${encodeURIComponent(sku)}/stockItems/1\`, {
    method:'PUT',
    body: j({ stockItem: { qty: Number(stock.quantity||0), is_in_stock: Number(stock.status||1) === 1 ? 1 : 0 } })
  });
  if (legacy.ok) return true;
  throw new Error('Stock update failed');
};

module.exports = (app) => {`);
}

// 3) I heal-handleren: etter produkt/variant-arbeid, sørg for at vi forsøker stock når body.stock finnes
out = out.replace(
  /(\/\/\s*2\)\s*Fallback:.*?\n)([\s\S]*?)(res\.json\(\s*\{\s*ok:\s*true[\s\S]*?\}\s*\)\s*;)/,
  (m, p1, p2, p3) => {
    // injiser blokk før retur
    const inject = `
      // patched: always try stock when provided
      if (body && body.stock) {
        try {
          await upsertStock(sku, body.stock);
          extra.stockUpdated = true;
        } catch (e) {
          extra.stockError = String(e && e.message || e);
        }
      }
    `;
    // sørg for at vi har 'extra' i svaret
    let replaced = m;
    if (!/const\s+extra\s*=/.test(replaced)) {
      replaced = replaced.replace(/(let|const)\s+\{\s*parentSku\s*,\s*sku[\s\S]*?\};/, (mm) => `${mm}\nconst extra = {};`);
      replaced = replaced.replace(/(\{[^}]*ok:\s*true[^}]*)(\})\s*\)\s*;/, '$1, ...extra $2);');
    } else {
      replaced = replaced.replace(/(\{[^}]*ok:\s*true[^}]*)(\})\s*\)\s*;/, '$1, ...extra $2);');
    }
    replaced = replaced.replace(p3, `${inject}\n${p3}`);
    return replaced;
  }
);

// 4) Sørg for at svaret inkluderer stockUpdated/stockError om vi allerede returnerer body/fallback
if (!/stockUpdated/.test(out)) {
  out = out.replace(/res\.json\(\s*\{\s*ok:\s*true([^}]*)\}\s*\)\s*;/g,
    (mm, rest) => `res.json({ ok: true${rest}, ...(typeof extra==='object'?extra:{}) });`);
}

fs.writeFileSync(file, out, 'utf8');
console.log('✅ Patchet routes-variants.js: stock oppdateres når payload inkluderer stock, og svar inkluderer stockUpdated/stockError.');

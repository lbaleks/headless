const express = require('express');
const router = express.Router();
const fetch = (...args) => (globalThis.fetch ? globalThis.fetch(...args) : import('node-fetch').then(({default:f})=>f(...args)));
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

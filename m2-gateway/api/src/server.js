const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });

const express = require('express');
const axios = require('axios');
const morgan = require('morgan');
const cors = require('cors');

const app = express();
app.use(express.json());
app.use(cors());
app.use(morgan('dev'));

const PORT = process.env.PORT || 3000;
const MAGENTO_BASE = process.env.MAGENTO_BASE;
const MAGENTO_TOKEN = (process.env.MAGENTO_TOKEN || '').trim();
const TIMEOUT = Number(process.env.MAGENTO_TIMEOUT_MS || 25000);

if (!MAGENTO_BASE || !MAGENTO_TOKEN) {
  console.error('Missing MAGENTO_BASE or MAGENTO_TOKEN in .env');
  process.exit(1);
}

const magento = axios.create({
  baseURL: MAGENTO_BASE,
  timeout: TIMEOUT,
  headers: {
    'Authorization': MAGENTO_TOKEN.startsWith('Bearer ') ? MAGENTO_TOKEN : `Bearer ${MAGENTO_TOKEN}`,
    'Content-Type': 'application/json'
  }
});

// Health
app.get('/health/magento', async (_req, res) => {
  try {
    await magento.get('/rest/V1/store/websites');
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ ok: false, error: e?.response?.data || e.message });
  }
});

// Variant heal (forenklet – matcher curl du brukte)
app.post('/ops/variant/heal', async (req, res) => {
  const { parentSku, sku, cfgAttr, cfgValue, label, websiteId, stock } = req.body || {};
  if (!parentSku || !sku || !cfgAttr || typeof cfgValue === 'undefined') {
    return res.status(400).json({ error: 'Missing required fields' });
  }
  try {
    // 1) Upsert simple
    await magento.put(`/rest/V1/products/${encodeURIComponent(sku)}`, {
      product: {
        sku,
        name: `AUTOGEN ${label || ''}`.trim(),
        type_id: 'simple',
        attribute_set_id: 4,
        visibility: 1,
        status: 1,
        price: 0,
        weight: 0,
        extension_attributes: { website_ids: websiteId ? [Number(websiteId)] : undefined },
        custom_attributes: [{ attribute_code: cfgAttr, value: cfgValue }]
      }
    });

    // 2) Stock (MSI)
    if (stock && stock.source_code && typeof stock.quantity !== 'undefined') {
      await magento.post('/rest/V1/inventory/source-items', {
        sourceItems: [{
          sku, source_code: stock.source_code,
          quantity: Number(stock.quantity),
          status: Number(stock.status ?? 1)
        }]
      }).catch(() => {}); // idempotent
    }

    // 3) Ensure parent option includes value
    const parent = await magento.get(`/rest/all/V1/products/${encodeURIComponent(parentSku)}?fields=extension_attributes`);
    const attrs = parent.data?.extension_attributes?.configurable_product_options || [];
    const opt = attrs.find(o => String(o.attribute_code) === cfgAttr || String(o.label).toLowerCase().includes('color') || String(o.attribute_id));
    if (!opt) {
      // Hent attribute_id
      const attrMeta = await magento.get(`/rest/all/V1/products/attributes/${encodeURIComponent(cfgAttr)}`);
      const attribute_id = String(attrMeta.data.attribute_id);
      const values = [{ value_index: Number(cfgValue) }];
      await magento.post(`/rest/all/V1/configurable-products/${encodeURIComponent(parentSku)}/options`, {
        option: { attribute_id, label: cfgAttr, position: 0, is_use_default: true, values }
      }).catch(() => {});
    } else {
      const existing = (opt.values || []).map(v => v.value_index);
      if (!existing.includes(Number(cfgValue))) {
        existing.push(Number(cfgValue));
        await magento.put(`/rest/all/V1/configurable-products/${encodeURIComponent(parentSku)}/options/${opt.id}`, {
          option: { id: opt.id, attribute_id: opt.attribute_id, values: existing.map(v => ({ value_index: v })) }
        }).catch(() => {});
      }
    }

    // 4) Attach child (idempotent)
    await magento.post(`/rest/V1/configurable-products/${encodeURIComponent(parentSku)}/child`, { childSku: sku })
      .catch(err => {
        const msg = err?.response?.data?.message || '';
        if (!/already attached/i.test(msg)) throw err;
      });

    res.json({ ok: true, sku, parentSku, cfgAttr, cfgValue });
  } catch (e) {
    res.status(500).json({ ok: false, error: e?.response?.data || e.message });
  }
});

// Category replace
app.post('/ops/category/replace', async (req, res) => {
  const items = req.body?.items || [];
  if (!Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ error: 'items: [{sku, categoryIds:number[]}] required' });
  }
  try {
    const results = [];
    for (const it of items) {
      const sku = it.sku;
      const ids = (it.categoryIds || []).map(Number).filter(n => Number.isFinite(n));
      const links = ids.map(id => ({ position: 0, category_id: String(id) }));
      const r = await magento.put(`/rest/V1/products/${encodeURIComponent(sku)}`, {
        product: { sku, extension_attributes: { category_links: links } }
      });
      results.push({ sku, categoryIds: ids, ok: true, name: r.data?.name });
    }
    res.json({ ok: true, items: results });
  } catch (e) {
    res.status(500).json({ ok: false, error: e?.response?.data || e.message });
  }
});

app.listen(PORT, () => {
  console.log(`# m2-gateway up on http://localhost:${PORT}`);
});

/** — simple in-memory stats (stub) — */
app.get('/ops/stats/summary', async (req, res) => {
  try {
    // her kan vi senere hente ekte tall fra Magento
    res.json({
      ok: true,
      ts: new Date().toISOString(),
      totals: { products: 3, categories: 7, variants: 4 },
    });
  } catch (err) {
    res.status(500).json({ ok: false, error: String(err && err.message || err) });
  }
});

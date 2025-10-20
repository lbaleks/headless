// server.js
const express = require('express');
const axios = require('axios');
const dotenv = require('dotenv');
dotenv.config();

const app = express();
app.use(express.json({ limit: '1mb' }));

const BASE = process.env.MAGENTO_BASE;
const TIMEOUT = Number(process.env.MAGENTO_TIMEOUT_MS || 25000);
const AUTH = `Authorization: ${process.env.MAGENTO_TOKEN.replace(/^Bearer\s*/,'Bearer ')}`;

const api = axios.create({
  baseURL: BASE,
  timeout: TIMEOUT,
  headers: {
    'Content-Type': 'application/json',
    'Authorization': AUTH.split(': ').pop(), // bare "Bearer <...>"
  },
});

// ---- helpers ----
const READ = (p, cfg={}) => api.get(`/rest/all/V1${p}`, cfg).then(r=>r.data);
const WRITE = (method, p, data, cfg={}) =>
  api.request({ method, url: `/rest/V1${p}`, data, ...cfg }).then(r=>r.data);

async function getAttributeId(code){
  const a = await READ(`/products/attributes/${code}`);
  return a.attribute_id; // string
}
async function getParentOptions(parentSku){
  const p = await READ(`/products/${encodeURIComponent(parentSku)}?fields=extension_attributes`);
  return p.extension_attributes?.configurable_product_options || [];
}
async function ensureOptionHasValueIndex(parentSku, attrId, valueIndex){
  const opts = await getParentOptions(parentSku);
  const opt = opts.find(o => String(o.attribute_id) === String(attrId));
  if (!opt) return; // parent har ikke satt opp denne attributten her (men attach kan fortsatt fungere)
  const values = (opt.values || []).map(v => v.value_index);
  if (values.includes(valueIndex)) return;
  const merged = Array.from(new Set([...values, valueIndex])).map(v => ({ value_index: v }));
  await WRITE('PUT', `/configurable-products/${encodeURIComponent(parentSku)}/options/${opt.id}`, {
    option: { ...opt, values: merged }
  });
}

async function upsertSimple({ sku, name, websiteId=1, price=399, weight=1, status=1, visibility=1, cfgAttr, cfgValue }){
  const product = {
    sku, name, type_id: 'simple',
    attribute_set_id: 4, price, weight, status, visibility,
    extension_attributes: { website_ids: [websiteId] },
    custom_attributes: cfgAttr ? [{ attribute_code: cfgAttr, value: cfgValue }] : []
  };
  return WRITE('PUT', `/products/${encodeURIComponent(sku)}`, { product });
}
async function setSourceItems(sourceItems){
  // [{sku, source_code:'default', quantity:5, status:1}]
  return WRITE('POST', `/inventory/source-items`, { sourceItems });
}
async function attachChild(parentSku, childSku){
  try {
    await WRITE('POST', `/configurable-products/${encodeURIComponent(parentSku)}/child`, { childSku });
    return true;
  } catch (e){
    const msg = e?.response?.data?.message || '';
    if (msg.includes('already attached')) return true;
    throw e;
  }
}
async function getChildren(parentSku){
  return READ(`/configurable-products/${encodeURIComponent(parentSku)}/children`);
}

// ---- endpoints ----

// Health
app.get('/health/magento', async (req,res)=>{
  try {
    await api.get('/rest/V1/store/websites');
    res.json({ ok:true });
  } catch (e){
    res.status(500).json({ ok:false, error: e?.response?.data || String(e) });
  }
});

// 1) Variant heal
app.post('/ops/variant/heal', async (req,res)=>{
  const { parentSku, sku, cfgAttr, cfgValue, label='Auto', websiteId=1, stock } = req.body || {};
  if (!parentSku || !sku) return res.status(400).json({ error:'parentSku og sku er påkrevd' });
  try {
    // 1) upsert simple
    await upsertSimple({ sku, name: `${(label||'').trim() || 'Variant'} ${cfgValue ?? ''}`.trim(), websiteId, cfgAttr, cfgValue });

    // 2) stock
    if (stock?.sku || stock?.quantity != null) {
      const payload = [{ sku, source_code: stock.source_code || 'default', quantity: Number(stock.quantity||0), status: Number(stock.status||1) }];
      await setSourceItems(payload);
    }

    // 3) ensure option has valueIndex (best effort)
    if (cfgAttr && (cfgValue ?? null) !== null){
      const attrId = await getAttributeId(cfgAttr);
      await ensureOptionHasValueIndex(parentSku, attrId, Number(cfgValue));
    }

    // 4) attach
    await attachChild(parentSku, sku);

    // 5) verify
    const ch = await getChildren(parentSku);
    res.json({ ok:true, children: ch.map(c=>c.sku) });
  } catch (e){
    res.status(500).json({ ok:false, error: e?.response?.data || String(e) });
  }
});

// 2) Attach child (idempotent)
app.post('/ops/configurable/attach', async (req,res)=>{
  const { parentSku, childSku } = req.body || {};
  if (!parentSku || !childSku) return res.status(400).json({ error:'parentSku og childSku er påkrevd' });
  try {
    await attachChild(parentSku, childSku);
    const ch = await getChildren(parentSku);
    res.json({ ok:true, children: ch.map(c=>c.sku) });
  } catch (e){
    res.status(500).json({ ok:false, error: e?.response?.data || String(e) });
  }
});

app.get("/ops/stats/summary", async (req, res) => {
  try {
    const token = process.env.MAGENTO_TOKEN;
    const base = process.env.MAGENTO_BASE;
    const headers = { Authorization: token, "Content-Type": "application/json" };

    const [products, orders, customers] = await Promise.all([
      fetch(`${base}/rest/V1/products?searchCriteria[pageSize]=1`, { headers }),
      fetch(`${base}/rest/V1/orders?searchCriteria[pageSize]=1`, { headers }),
      fetch(`${base}/rest/V1/customers/search?searchCriteria[pageSize]=1`, { headers }),
    ]);

    res.json({
      ok: true,
      products: (await products.json()).total_count || 0,
      orders: (await orders.json()).total_count || 0,
      customers: (await customers.json()).total_count || 0,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ ok: false, error: err.message });
  }
});

// 3) Category replace (exact match)
app.post('/ops/category/replace', async (req,res)=>{
  const { items=[] } = req.body || {};
  try {
    const results = [];
    for (const it of items){
      const sku = it.sku;
      const ids = (it.categoryIds || []).filter(n=>Number.isFinite(n)).map(n=>String(Number(n)));
      const links = ids.map(id => ({ position:0, category_id: id }));
      await WRITE('PUT', `/products/${encodeURIComponent(sku)}`, {
        product: { sku, extension_attributes: { category_links: links } }
      });
      results.push({ sku, categoryIds: ids });
    }
    res.json({ ok:true, updated: results });
  } catch (e){
    res.status(500).json({ ok:false, error: e?.response?.data || String(e) });
  }
});

const port = Number(process.env.PORT || 3000);
app.listen(port, ()=> console.log(`m2-gateway up on http://localhost:${port}`));
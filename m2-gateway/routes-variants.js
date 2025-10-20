
async function upsertStock({ sku, source_code, quantity, status }) {
  const j = (x) => JSON.stringify(x);

  // 1) MSI wrapper-shape
  let r = await mfetch(`/rest/V1/inventory/source-items`, {
    method: "POST",
    body: j({ sourceItems: [{ sku, source_code, quantity, status }] }),
  });
  if (r.ok) return true;

  // 2) MSI raw array
  if (r.status === 400 || r.status === 415) {
    const r2 = await mfetch(`/rest/V1/inventory/source-items`, {
      method: "POST",
      body: j([{ sku, source_code, quantity, status }]),
    });
    if (r2.ok) return true;
    r = r2; // behold siste feilsvar
  }

  // 3) Legacy fallback
  if (r.status === 404 || r.status === 400) {
    const legacy = await mfetch(`/rest/V1/products/${encodeURIComponent(sku)}/stockItems/1`, {
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
    throw new Error(`Legacy stock update failed: ${JSON.stringify(legacy.data)}`);
  }

  throw new Error(`Stock update failed: ${JSON.stringify(r.data)}`);
}

module.exports = (app) => {
  const BASE  = (process.env.MAGENTO_BASE  || '').trim();
  let   TOKEN = (process.env.MAGENTO_TOKEN || '').trim();
  if (TOKEN && !/^Bearer\s/.test(TOKEN)) TOKEN = 'Bearer ' + TOKEN;
  if (!BASE || !TOKEN) throw new Error('Missing MAGENTO_BASE or MAGENTO_TOKEN');

  const j = (x) => JSON.stringify(x);
  const headers = { 'Content-Type':'application/json', 'Authorization': TOKEN };

  const fetchFn = (...args) =>
    (globalThis.fetch ? globalThis.fetch(...args)
      : import('node-fetch').then(({default: f}) => f(...args)));

  const mfetch = async (path, opts = {}) => {
    const url = BASE.replace(/\/+$/,'') + path;
    const res = await fetchFn(url, { headers, ...opts });
    const ct = (res.headers && res.headers.get && res.headers.get('content-type')) || '';
    let data = null;
    try { data = ct.includes('json') ? await res.json() : await res.text(); } catch (_) {}
    return { ok: res.ok, status: res.status, data };
  };

  // MSI → (evt.) raw array → Legacy PUT fallback
  const upsertStock = async ({ sku, source_code = 'default', quantity = 0, status = 1 }) => {
    const q = Number(quantity || 0);
    const s = Number(status   || 1);

    // Try #1: MSI wrapper
    let r = await mfetch('/rest/V1/inventory/source-items', {
      method: 'POST',
      body: j({ sourceItems: [{ sku, source_code, quantity: q, status: s }] })
    });
    if (r.ok) return true;

    // Try #2: MSI raw array når feilen peker på "sourceItems"
    const msg = (r.data && (r.data.message || r.data)) || '';
    if (Number(r.status || 0) === 400 && String(msg).toLowerCase().includes('sourceitems')) {
      const r2 = await mfetch('/rest/V1/inventory/source-items', {
        method: 'POST',
        body: j([{ sku, source_code, quantity: q, status: s }])
      });
      if (r2.ok) return true;
      r = r2; // ta vare på sist svar
    }

    // Try #3: Legacy stock når MSI gir 400/401/403/404
    if ([400,401,403,404].includes(Number(r.status || 0))) {
      const legacy = await mfetch(`/rest/V1/products/${encodeURIComponent(sku)}/stockItems/1`, {
        method: 'PUT',
        body: j({ stockItem: { qty: q, is_in_stock: s === 1 ? 1 : 0 } })
      });
      if (legacy.ok) return true;
      throw new Error('Legacy stock update failed: ' + JSON.stringify(legacy.data));
    }

    // Ellers: rapporter MSI-feilen
    throw new Error('Stock update failed: ' + JSON.stringify(r.data));
  };

  // Minimal no-op; utvid etter behov (sikre at variant finnes etc.)
  const ensureProduct = async ({ sku/*, label, cfgAttr, cfgValue*/ }) => {
    if (!sku) throw new Error('Missing sku');
    return true;
  };

  app.post('/ops/variant/heal', async (req, res) => {
    try {
      const body = req.body || {};
      const { parentSku, sku, cfgAttr, cfgValue, label, websiteId, stock } = body;

      // 1) Prøv custom modul-endpoint (hvis miljøet har det)
      let probe;
      try {
        probe = await mfetch('/rest/V1/litebrygg/ops/variant/heal', { method: 'POST', body: j(body) });
      } catch (e) {
        probe = { ok: false, status: 0, data: String(e) };
      }
      if (probe && probe.status !== 404) {
        if (probe.ok) return res.json({ ok: true, ...(probe.data || {}), fallback: false });
        return res.status(400).json({ ok: false, error: probe.data });
      }

      // 2) Fallback i gateway
      await ensureProduct({ sku, label: label || sku, cfgAttr, cfgValue });
      if (stock && stock.source_code) {
        try {
          await upsertStock({ sku, ...stock });
        } catch (e) {
          return res.status(400).json({ ok: false, error: { message: String(e.message || e) } });
        }
      }

      return res.json({ ok: true, fallback: true, sku, parentSku, cfgAttr, cfgValue, label, websiteId , ...(typeof extra==='object'?extra:{}) });
    } catch (e) {
      return res.status(500).json({ ok: false, error: { message: String(e.message || e) } });
    }
  });
};

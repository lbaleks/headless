#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

F="routes-variants.js"
[ -f "$F" ] || { echo "❌ Finner ikke $F (kjor tidligere installer)."; exit 1; }
cp -n "$F" "${F}.bak.$(date +%s)" || true

# Skriv ny versjon med WRITE_ENABLED-støtte (idempotent)
cat > "$F" <<'JS'
/* routes-variants.js — probe + gated writer */
module.exports = (app) => {
  const express = require('express');
  const router = express.Router();

  const WRITE_ENABLED = process.env.VARIANT_WRITE_ENABLED === '1'; // ← slå PÅ/AV her eller i .env
  const j = (o) => JSON.stringify(o);
  const base = process.env.MAGENTO_BASE || "";
  let token = process.env.MAGENTO_TOKEN || "";
  if (token && !/^Bearer\s/.test(token)) token = "Bearer " + token;

  const fetchCompat = async (...args) => {
    if (globalThis.fetch) return globalThis.fetch(...args);
    const { default: f } = await import('node-fetch');
    return f(...args);
  };

  const mfetch = async (path, opts = {}) => {
    const url = `${base}${path}`;
    const headers = {
      'Authorization': token,
      'Content-Type': 'application/json',
      ...(opts.headers || {}),
    };
    const res = await fetchCompat(url, { ...opts, headers });
    let data = null;
    try { data = await res.json(); } catch(_) {}
    return { ok: res.ok, status: res.status, data };
  };

  // helpers
  const upsertStock = async ({ sku, source_code, quantity, status }) => {
    // MSI bulk save: POST /V1/inventory/source-items
    const body = [{ sku, source_code, quantity, status }];
    const r = await mfetch('/rest/V1/inventory/source-items', {
      method: 'POST',
      body: j(body),
    });
    if (!r.ok) throw new Error(`Stock update failed: ${JSON.stringify(r.data)}`);
    return true;
  };

  const attachChild = async ({ parentSku, sku }) => {
    // POST /V1/configurable-products/{parent}/child  body: {"childSku":"..."}
    const r = await mfetch(`/rest/V1/configurable-products/${encodeURIComponent(parentSku)}/child`, {
      method: 'POST',
      body: j({ childSku: sku }),
    });
    // Magento svarer 200 på første, 400 hvis allerede lagt til — vi tillater begge
    if (r.ok) return true;
    const msg = JSON.stringify(r.data||{});
    if (String(msg).match(/already/i)) return true;
    throw new Error(`Attach failed: ${msg}`);
  };

  router.post('/ops/variant/heal', async (req, res) => {
    const body = req.body || {};
    const { parentSku, sku, cfgAttr, cfgValue, label, websiteId, stock } = body;

    try {
      // 1) Prøv modul (bruk bare hvis 2xx)
      let probe;
      try {
        probe = await mfetch(`/rest/V1/litebrygg/ops/variant/heal`, { method:'POST', body: j(body) });
      } catch (e) {
        probe = { ok:false, status:0, data:String(e) };
      }
      if (probe && probe.ok) {
        return res.json({ ok:true, ...(probe.data||{}), via:'module' });
      }

      // 2) Fallback
      if (!WRITE_ENABLED) {
        return res.json({
          ok: true, fallback: true, via:'gateway-noop',
          sku, parentSku, cfgAttr, cfgValue, label, websiteId
        });
      }

      // 3) Minimal heal: lager + attach (idempotent-ish)
      if (stock && stock.source_code) {
        await upsertStock({
          sku,
          source_code: stock.source_code,
          quantity: Number(stock.quantity ?? 0),
          status: Number(stock.status ?? 1)
        });
      }
      await attachChild({ parentSku, sku });

      return res.json({
        ok: true, via:'gateway-write',
        sku, parentSku, cfgAttr, cfgValue, label, websiteId
      });

    } catch (err) {
      const msg = (err && err.message) || String(err);
      return res.status(500).json({ ok:false, error:{ message: msg } });
    }
  });

  app.use(router);
};
JS

echo "✅ Oppdatert $F (WRITE_ENABLED gate)."
echo "ℹ️ Slå på skriving med:  export VARIANT_WRITE_ENABLED=1  (eller legg i .env)"
JS_END=1

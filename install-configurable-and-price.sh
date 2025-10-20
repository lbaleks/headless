#!/usr/bin/env bash
set -euo pipefail

# ---------- locate dirs ----------
GATEWAY_DIR="$(find "$HOME/Documents/M2" -type d -name m2-gateway | head -n1 || true)"
if [[ -z "${GATEWAY_DIR:-}" || ! -d "$GATEWAY_DIR" ]]; then
  echo "❌ Fant ikke m2-gateway under $HOME/Documents/M2"
  exit 1
fi

cd "$GATEWAY_DIR"

# ---------- util ----------
cat > routes-util.js <<'JS'
const fetch = (...args)=> (globalThis.fetch?globalThis.fetch(...args):import('node-fetch').then(({default:f})=>f(...args)));
const j = x => JSON.stringify(x);
const base = (process.env.MAGENTO_BASE||process.env.M2_BASE_URL||'').replace(/\/+$/,'');
const token = process.env.MAGENTO_TOKEN || (process.env.M2_ADMIN_TOKEN ? `Bearer ${process.env.M2_ADMIN_TOKEN}` : '');

async function mfetch(path, opts={}) {
  if (!base || !token) {
    return { ok:false, status:0, data:{message:"Missing MAGENTO_BASE/MAGENTO_TOKEN (eller M2_BASE_URL/M2_ADMIN_TOKEN)"} };
  }
  const url = /^[a-z]+:\/\//i.test(path) ? path : `${base}${path}`;
  const headers = {'Content-Type':'application/json', 'Authorization': token, ...(opts.headers||{})};
  const res = await fetch(url, {...opts, headers});
  let data=null; try{ data = await res.json(); } catch(_){}
  return { ok: res.ok, status: res.status, data };
}

module.exports = { fetch, j, base, token, mfetch };
JS

# ---------- configurable link route ----------
cat > routes-configurable.js <<'JS'
const express = require('express');
const { mfetch, j } = require('./routes-util');

module.exports = (app)=>{
  const r = express.Router();

  // POST /ops/configurable/link
  // body: { parentSku, childSku, attrCode, valueIndex }
  r.post('/link', async (req,res)=>{
    const b = req.body || {};
    const parentSku = b.parentSku, childSku = b.childSku, attrCode = b.attrCode, valueIndex = b.valueIndex;
    if (!parentSku || !childSku || !attrCode || (valueIndex===undefined)) {
      return res.status(400).json({ ok:false, error: 'Missing one of parentSku, childSku, attrCode, valueIndex' });
    }

    // 1) attribute_id for attrCode
    const a = await mfetch(`/rest/V1/products/attributes/${encodeURIComponent(attrCode)}`);
    if (!a.ok || !a.data?.attribute_id) {
      return res.status(400).json({ ok:false, error:`Could not resolve attribute_id for ${attrCode}`, detail:a.data });
    }
    const attribute_id = a.data.attribute_id;

    // 2) eksisterende options
    const cur = await mfetch(`/rest/V1/configurable-products/${encodeURIComponent(parentSku)}/options/all`);
    const hasOption = Array.isArray(cur.data) && cur.data.some(o => String(o.attribute_id) === String(attribute_id));

    // 3) opprett/oppdater option
    if (!hasOption) {
      await mfetch(`/rest/V1/configurable-products/${encodeURIComponent(parentSku)}/options`, {
        method: 'POST',
        body: j({ option: {
          attribute_id: Number(attribute_id),
          label: attrCode,
          values: [{ value_index: Number(valueIndex) }]
        }})
      });
    } else {
      try {
        const opt = (cur.data||[]).find(o => String(o.attribute_id) === String(attribute_id));
        if (opt?.id) {
          const existingVals = new Set((opt.values||[]).map(v=>Number(v.value_index)));
          existingVals.add(Number(valueIndex));
          await mfetch(`/rest/V1/configurable-products/${encodeURIComponent(parentSku)}/options/${opt.id}`, {
            method: 'PUT',
            body: j({ option: {
              attribute_id: Number(attribute_id),
              id: opt.id,
              label: opt.label || attrCode,
              values: [...existingVals].map(v=>({value_index:v}))
            }})
          });
        }
      } catch(_) {}
    }

    // 4) link child
    const link = await mfetch(`/rest/V1/configurable-products/${encodeURIComponent(parentSku)}/child`, {
      method: 'POST',
      body: j({ childSku })
    });
    if (link.ok || link.status===400) {
      return res.json({ ok:true, parentSku, childSku, attrCode, valueIndex, linked:true, note: link.status===400?'maybe-already-linked':undefined });
    }
    return res.status(400).json({ ok:false, error:'Link child failed', detail:link.data });
  });

  app.use('/ops/configurable', r);
};
JS

# ---------- price route ----------
cat > routes-price.js <<'JS'
const express = require('express');
const { mfetch, j } = require('./routes-util');

module.exports = (app)=>{
  const r = express.Router();

  // POST /ops/price/upsert
  // body: { sku, price } + optional { special_price, special_from_date, special_to_date }
  r.post('/upsert', async (req,res)=>{
    const b = req.body || {};
    const { sku, price, special_price, special_from_date, special_to_date } = b;
    if (!sku || (price===undefined && special_price===undefined)) {
      return res.status(400).json({ ok:false, error: 'Missing sku or price/special_price' });
    }
    const product = { sku };
    if (price!==undefined) product.price = Number(price);
    if (special_price!==undefined) product.special_price = Number(special_price);
    if (special_from_date) product.special_from_date = String(special_from_date);
    if (special_to_date) product.special_to_date = String(special_to_date);

    const r1 = await mfetch(`/rest/V1/products/${encodeURIComponent(sku)}`, {
      method: 'PUT',
      body: j({ product })
    });
    if (!r1.ok) return res.status(400).json({ ok:false, error:'Price update failed', detail:r1.data });
    return res.json({ ok:true, sku, price, special_price, special_from_date, special_to_date });
  });

  app.use('/ops/price', r);
};
JS

# ---------- wire into server.js (no $1 usage) ----------
insert_after_products() {
  # insert require lines after routes-products if present, else before app.listen
  if grep -q "require('./routes-products')" server.js; then
    perl -0777 -pe "s|(require\\(\\s*['\\\"]\\./routes-products['\\\"]\\)\\(app\\)\\s*;)|\\1\nrequire('./routes-configurable')(app);\nrequire('./routes-price')(app);|s" -i server.js || true
  fi
  if ! grep -q "routes-configurable" server.js; then
    node -e "const fs=require('fs');let s=fs.readFileSync('server.js','utf8');s=s.replace(/(app\\.listen[^\n]*\\n)/,'require(\\'./routes-configurable\\')(app);\n$1');fs.writeFileSync('server.js',s)"
  fi
  if ! grep -q "routes-price" server.js; then
    node -e "const fs=require('fs');let s=fs.readFileSync('server.js','utf8');s=s.replace(/(app\\.listen[^\n]*\\n)/,'require(\\'./routes-price\\')(app);\n$1');fs.writeFileSync('server.js',s)"
  fi
}
insert_after_products

echo "✅ Ruter installert: /ops/configurable/link og /ops/price/upsert"
echo "➡️  Restart gateway:"
echo "    pkill -f \"/Users/$USER/Documents/M2/m2-gateway/server.js\" 2>/dev/null || true"
echo "    node /Users/$USER/Documents/M2/m2-gateway/server.js"

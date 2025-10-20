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

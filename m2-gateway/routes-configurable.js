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

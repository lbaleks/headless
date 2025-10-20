const fetch = (...args)=> (globalThis.fetch?globalThis.fetch(...args):import('node-fetch').then(({default:f})=>f(...args)));
const J = (x)=>JSON.stringify(x);
const base = (process.env.MAGENTO_BASE||'').replace(/\/+$/,'');
const token = process.env.MAGENTO_TOKEN||'';

async function mfetch(path, opts={}){
  const url = /^[a-z]+:\/\//i.test(path) ? path : `${base}${path}`;
  const headers = {'Content-Type':'application/json','Authorization':token, ...(opts.headers||{})};
  const res = await fetch(url, {...opts, headers});
  let data=null; try{ data=await res.json(); }catch(_){}
  return {ok:res.ok, status:res.status, data};
}
async function probe(method, path, body){
  try{
    const r = await mfetch(path, {method, body: body==null?undefined:J(body)});
    if (r.ok) return {authorized:true, status:r.status, note:'OK'};
    if (r.status===400) return {authorized:true, status:r.status, note:r.data?.message||'400'};
    if (r.status===401||r.status===403) return {authorized:false, status:r.status, note:r.data?.message||String(r.status)};
    if (r.status===404) return {authorized:null, status:r.status, note:'Not Found'};
    return {authorized:null, status:r.status, note:r.data?.message||String(r.status)};
  }catch(e){ return {authorized:null, status:0, note:String(e)}; }
}

module.exports = (app)=>{
  app.get('/ops/acl/check', async (_req,res)=>{
    const checks = [
      {key:'MSI_source_items',        requires:'Magento_InventoryApi::source_items',
        res: await probe('POST','/rest/V1/inventory/source-items', {sourceItems:[{sku:'X',source_code:'default',quantity:1,status:1}]})},
      {key:'Legacy_catalog_inventory', requires:'Magento_Catalog::catalog_inventory',
        res: await probe('PUT','/rest/V1/products/TEST/stockItems/1', {stockItem:{qty:1,is_in_stock:1}})},
      {key:'Catalog_products',         requires:'Magento_Catalog::products',
        res: await probe('PUT','/rest/V1/products/TEST', {product:{sku:'TEST'}})},
      {key:'Configurable_manage',      requires:'Magento_ConfigurableProduct::configurable',
        res: await probe('POST','/rest/V1/configurable-products/TEST-CFG/child', {childSku:'X'})},
    ];
    const summary = checks.map(c=>({check:c.key, requires:c.requires, ...c.res}));
    res.json({ ok:true, summary,
      missing: summary.filter(s=>s.authorized===false).map(s=>s.requires),
      unknown: summary.filter(s=>s.authorized===null)
    });
  });
};

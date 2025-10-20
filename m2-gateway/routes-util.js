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

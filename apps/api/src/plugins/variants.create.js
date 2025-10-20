import { fetch } from 'undici'
import 'dotenv/config'

const BASE = process.env.M2_BASE_URL || ''
const TOKEN = process.env.M2_ADMIN_TOKEN || ''
const VAR_ATTR = process.env.VARIANT_ATTRIBUTE || 'size'  // kan overstyres i .env

function badEnv () {
  const miss=[]
  if(!BASE) miss.push('M2_BASE_URL')
  if(!TOKEN) miss.push('M2_ADMIN_TOKEN')
  return miss
}
async function m2call(path, {method='GET', body}={}) {
  const r = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      'Content-Type': 'application/json'
    },
    body: body ? JSON.stringify(body) : undefined
  })
  const txt = await r.text()
  let data; try{ data = JSON.parse(txt) } catch { data={ raw: txt } }
  if(!r.ok) throw Object.assign(new Error(`Upstream ${r.status}`), { status:r.status, data })
  return data
}
async function getAttrByCode(code){
  // /rest/V1/products/attributes/:attributeCode
  return m2call(`/rest/V1/products/attributes/${encodeURIComponent(code)}`)
}
async function ensureConfigurableParent(fromSku, cfgSku, superAttrId){
  // Hent original
  const src = await m2call(`/rest/V1/products/${encodeURIComponent(fromSku)}`)
  // Lag konfigurerbar parent (enkelt minimum)
  const payload = {
    product: {
      sku: cfgSku,
      name: src.name,
      attribute_set_id: src.attribute_set_id,
      price: src.price ?? 0,
      status: 1,
      visibility: 4,
      type_id: "configurable",
      extension_attributes: {
        configurable_product_options: [{
          attribute_id: String(superAttrId),
          label: VAR_ATTR,
          values: [], // fylles ved første child
          position: 0
        }],
        configurable_product_links: []
      },
      custom_attributes: src.custom_attributes?.filter(a => !['url_key'].includes(a.attribute_code))
    }
  }
  return m2call(`/rest/V1/products`, { method:'POST', body: payload })
}
async function createChildSimple({sku, name, attribute_set_id, price, weight, superAttrCode, superAttrValue, parentSku}){
  // Barn må ha verdi for super-attributtet (eks. size)
  const payload = {
    product: {
      sku,
      name,
      attribute_set_id,
      price,
      status: 1,
      visibility: 1, // ikke list som eget produkt i katalog
      type_id: "simple",
      weight: weight ?? 1,
      extension_attributes: {},
      custom_attributes: [
        { attribute_code: superAttrCode, value: superAttrValue }
      ]
    },
    saveOptions: true
  }
  const child = await m2call(`/rest/V1/products`, { method:'POST', body: payload })

  // Lenke barn til parent
  await m2call(`/rest/V1/configurable-products/${encodeURIComponent(parentSku)}/child`, {
    method:'POST',
    body: { childSku: child.sku }
  })
  return child
}

export default async function variantsCreate(app){
  // Bootstrap: /v2/integrations/magento/variants/bootstrap?from=TEST&cfg=TEST-CFG
  app.post('/v2/integrations/magento/variants/bootstrap', async (req, reply) => {
    const miss = badEnv()
    if(miss.length) return { ok:false, code:'env_missing', missing:miss }

    const from = req.query.from || req.query.src || req.body?.from
    const cfg = req.query.cfg || req.body?.cfg || (from ? `${from}-CFG` : undefined)
    const attrCode = req.query.attr || req.body?.attr || VAR_ATTR
    if(!from){ reply.code(400); return { ok:false, code:'bad_request', title:'from SKU required' } }

    try{
      const attr = await getAttrByCode(attrCode)
      if(!attr?.attribute_id){
        reply.code(400); return { ok:false, code:'missing_attribute', title:`Attribute "${attrCode}" not found in Magento` }
      }
      const res = await ensureConfigurableParent(from, cfg, attr.attribute_id)
      return { ok:true, parent: { sku: res.sku }, super_attribute:{ code: attrCode, id: attr.attribute_id } }
    }catch(e){
      reply.code(e.status||502); return { ok:false, code:'upstream_failed', detail: e.data }
    }
  })

  // Create + attach child: POST /v2/integrations/magento/products/:parent/variants
  // body: { sku, label, price, value, weight }
  app.post('/v2/integrations/magento/products/:parent/variants', async (req, reply) => {
    const miss = badEnv()
    if(miss.length) return { ok:false, code:'env_missing', missing:miss }

    // Admin-gating + idempotency er anbefalt; vi krever header her også:
    if(req.headers['x-role'] !== 'admin'){
      reply.code(403); return { ok:false, code:'forbidden', title:'Admin role required' }
    }

    const parentSku = req.params.parent
    const { sku, label, price, value, weight } = req.body || {}
    const attrCode = req.query.attr || VAR_ATTR
    if(!sku || !value){ reply.code(400); return { ok:false, code:'bad_request', title:'sku and value required' } }

    try{
      // slå opp parent + attribute
      const parent = await m2call(`/rest/V1/products/${encodeURIComponent(parentSku)}`)
      if(parent.type_id !== 'configurable'){
        reply.code(400); return { ok:false, code:'bad_parent', title:'Parent must be configurable' }
      }
      const attr = await getAttrByCode(attrCode)
      if(!attr?.attribute_id){
        reply.code(400); return { ok:false, code:'missing_attribute', title:`Attribute "${attrCode}" not found` }
      }
      const child = await createChildSimple({
        sku,
        name: label || `${parent.name} ${value}`,
        attribute_set_id: parent.attribute_set_id,
        price: price ?? parent.price ?? 0,
        weight: weight ?? 1,
        superAttrCode: attrCode,
        superAttrValue: value,
        parentSku
      })
      return { ok:true, child: { sku: child.sku }, parent: { sku: parentSku }, super_attribute: { code: attrCode, id: attr.attribute_id } }
    }catch(e){
      reply.code(e.status||502); return { ok:false, code:'upstream_failed', detail: e.data }
    }
  })
}

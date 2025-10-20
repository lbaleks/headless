
export type Rule =
  | { type:'base'; productId?:string; label?:string; price:number; currency?:string }
  | { type:'percent-off'; productId?:string; label?:string; percent:number }
  | { type:'amount-off'; productId?:string; label?:string; amount:number; currency?:string }
  | { type:'volume'; productId?:string; label?:string; tiers:{qtyFrom:number; price:number}[]; currency?:string }

export function computeEffective(product:any, rules:Rule[]){
  const currency = product?.currency || 'NOK'
  const applicable = rules.filter(r => !r.productId || String(r.productId)===String(product?.id))
  // base:
  const baseRule = (applicable.find(r=>r.type==='base') as any) || {type:'base', price: Number(product?.price||0), currency}
  const breakdown:any[] = [{label: baseRule.label||'Base', type:'base', value: baseRule.price}]
  let price = Number(baseRule.price||0)

  // non-tier adjustments (order: amount-off then percent-off)
  for(const r of applicable){
    if(r.type==='amount-off'){
      price = Math.max(0, price - Number(r.amount||0))
      breakdown.push({label:r.label||'Amount off', type:r.type, value: -Number(r.amount||0)})
    }
  }
  for(const r of applicable){
    if(r.type==='percent-off'){
      const delta = price * (Number(r.percent||0)/100)
      price = Math.max(0, price - delta)
      breakdown.push({label:r.label||'Percent off', type:r.type, value: -delta})
    }
  }

  // volume (read-only visning): sorter tiers
  const volume = applicable.find(r=>r.type==='volume') as any
  const tiers = Array.isArray(volume?.tiers)? [...volume.tiers].sort((a,b)=>a.qtyFrom-b.qtyFrom) : []

  return {
    currency,
    base: Number(baseRule.price||0),
    price: Number(price.toFixed(2)),
    breakdown,
    volumeTiers: tiers
  }
}

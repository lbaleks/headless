
export type Warehouse = { code:string; onHand:number; reserved:number; reorderPoint?:number; leadTimeDays?:number; moq?:number }
export type ProductInv = { id:string; sku:string; name:string; stock?:number; warehouses?:Warehouse[]; supplier?:string; supplierSku?:string }
export function totalAvailable(p:ProductInv){
  const base = Number(p.stock||0)
  const wh = (p.warehouses||[]).reduce((s,w)=> s + Number(w.onHand||0) - Number(w.reserved||0), 0)
  return base + wh
}
export function belowROP(p:ProductInv){
  return (p.warehouses||[]).some(w=>{
    const avail = Number(w.onHand||0) - Number(w.reserved||0)
    const rop = Number(w.reorderPoint||0)
    return rop>0 && avail < rop
  })
}
export function reorderDelta(p:ProductInv, code:string){
  const w=(p.warehouses||[]).find(x=>x.code===code)
  if(!w) return 0
  const avail = Number(w.onHand||0) - Number(w.reserved||0)
  const rop = Number(w.reorderPoint||0)
  const need = Math.max(0, rop - avail)
  const moq = Number(w.moq||0)
  if(need<=0) return 0
  return moq>0 ? Math.ceil(need / moq) * moq : need
}
export function suggestions(products:ProductInv[]){
  const out: { supplier:string, lines:{ sku:string, name:string, supplierSku?:string, warehouse:string, qty:number }[] }[] = []
  for(const p of products){
    for(const w of (p.warehouses||[])){
      const qty = reorderDelta(p, w.code)
      if(qty>0){
        const supplier = p.supplier || 'UNKNOWN'
        let grp = out.find(x=>x.supplier===supplier); if(!grp){ grp={supplier,lines:[]}; out.push(grp) }
        grp.lines.push({ sku:p.sku, name:p.name, supplierSku:p.supplierSku, warehouse:w.code, qty })
      }
    }
  }
  return out
}

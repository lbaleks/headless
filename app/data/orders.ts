// app/data/orders.ts
export type OrderStatus = "queued"|"exported"|"error"|"resolved";
export type OrderRow = { id:string; status:OrderStatus; msg?:string; updatedAt:number };

const mem = global as any;
if (!mem.__ORDERS__) {
  const now = Date.now();
  mem.__ORDERS__ = {
    rows: [
      { id:"10235", status:"queued",   msg:"Venter på eksport",     updatedAt: now-1000*60*7  },
      { id:"10234", status:"error",    msg:"Eksport feilet (ERP)",  updatedAt: now-1000*60*22 },
      { id:"10233", status:"exported", msg:"OK",                    updatedAt: now-1000*60*43 },
      { id:"10232", status:"queued",   msg:"Køet",                  updatedAt: now-1000*60*120 },
      { id:"10231", status:"error",    msg:"Mapping SKU",           updatedAt: now-1000*60*240 },
      { id:"10230", status:"exported", msg:"OK",                    updatedAt: now-1000*60*480 },
    ] as OrderRow[]
  };
}
export const ordersDB:{ rows:OrderRow[] } = mem.__ORDERS__;

export function listOrders(opts?:{ q?:string; status?:OrderStatus|"all"; limit?:number; offset?:number }){
  const { q="", status="all", limit=50, offset=0 } = opts||{};
  let x = [...ordersDB.rows].sort((a,b)=>b.updatedAt-a.updatedAt);
  if (status && status!=="all") x = x.filter(r=>r.status===status);
  if (q) {
    const s = q.toLowerCase();
    x = x.filter(r=> r.id.includes(q) || (r.msg||"").toLowerCase().includes(s));
  }
  const total = x.length;
  const page = x.slice(offset, offset+limit);
  return { total, items: page };
}

export function bulkAction(ids:string[], action:"retry"|"export"|"resolve"){
  const touched:string[] = [];
  for (const id of ids){
    const row = ordersDB.rows.find(r=>r.id===id);
    if (!row) continue;
    if (action==="retry")   row.status = "queued";
    if (action==="export")  row.status = "exported";
    if (action==="resolve") row.status = row.status==="error" ? "resolved" : row.status;
    row.updatedAt = Date.now();
    touched.push(id);
  }
  return { ok:true, ids:touched };
}

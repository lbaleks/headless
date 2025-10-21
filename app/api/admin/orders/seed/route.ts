export const runtime = 'nodejs';
// app/api/admin/orders/seed/route.ts
import { NextResponse } from "next/server";
import { ordersDB, type OrderRow } from "../../../../data/orders";

function pick<T>(xs:T[]) { return xs[Math.floor(Math.random()*xs.length)]; }

export async function POST(){
  try{
    const before = ordersDB.rows.length;
    const base: OrderRow[] = [
      { id:"10235", status:"queued",   msg:"Venter på eksport",     updatedAt: Date.now()-1000*60*7  },
      { id:"10234", status:"error",    msg:"Eksport feilet (ERP)",  updatedAt: Date.now()-1000*60*22 },
      { id:"10233", status:"exported", msg:"OK",                    updatedAt: Date.now()-1000*60*43 },
      { id:"10232", status:"queued",   msg:"Køet",                  updatedAt: Date.now()-1000*60*120 },
      { id:"10231", status:"error",    msg:"Mapping SKU",           updatedAt: Date.now()-1000*60*240 },
      { id:"10230", status:"exported", msg:"OK",                    updatedAt: Date.now()-1000*60*480 },
    ];

    if (before === 0) {
      ordersDB.rows.push(...base);
    } else {
      const statuses: OrderRow["status"][] = ["queued","exported","error","resolved"];
      const msgs = ["OK","Køet","Eksport feilet (ERP)","Mapping SKU","Venter på eksport"];
      const now = Date.now();
      for (let i=0;i<5;i++){
        const id = String(10000 + Math.floor(Math.random()*89999));
        ordersDB.rows.push({
          id,
          status: pick(statuses),
          msg: pick(msgs),
          updatedAt: now - Math.floor(Math.random()*1000*60*500),
        });
      }
    }
    const after = ordersDB.rows.length;
    return NextResponse.json({ ok:true, added: after-before, total: after, sample: ordersDB.rows.slice(0,10) });
  }catch(e:any){
    console.error("seed error:", e);
    return NextResponse.json({ ok:false, error:e?.message||"seed_failed", stack: e?.stack }, { status:500 });
  }
}

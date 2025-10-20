// app/api/admin/orders/bulk/route.ts
import { NextResponse } from "next/server";
import { bulkAction } from "../../../../data/orders";
import { append as audit } from "@/app/data/audit";

export async function POST(req:Request){
  try{
    const b = await req.json().catch(()=> ({}));
    const ids = Array.isArray(b?.ids) ? (b.ids as any[]).map(String) : [];
    const action = (b?.action as string)||"";
    if (!ids.length || !["retry","export","resolve"].includes(action)){
      return NextResponse.json({ ok:false, error:"bad_request" }, { status:400 });
    }
    const res = bulkAction(ids, action as any);
    audit({ actor:"admin", action:"orders.bulk."+action, target:"orders", meta:{ count: res.ids.length, ids: res.ids } });
    return NextResponse.json({ ok:true, ...res });
  }catch(e:any){
    console.error("orders bulk error:", e);
    return NextResponse.json({ ok:false, error:e?.message||"bulk_failed", stack: e?.stack }, { status:500 });
  }
}

// app/api/pricing/quote/route.ts
import { NextResponse } from "next/server";
import { append as audit } from "../../../data/audit";
import { quoteLine } from "../../../data/pricing";

export async function POST(req:Request){
  try{
    const b = await req.json().catch(()=> ({}));
    const { sku, qty, tier } = b || {};
    const q = quoteLine({ sku, qty, tier });
    audit({ actor:"admin", action:"pricing.quote", target:String(sku||""), meta:{ sku, qty, tier, ok: (q as any).ok, net: (q as any).net } });
    return NextResponse.json(q, { status: q.ok ? 200 : 400 });
  }catch(e:any){
    return NextResponse.json({ ok:false, error:e?.message||"bad_request" }, { status:400 });
  }
}

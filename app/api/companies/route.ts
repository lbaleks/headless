// app/api/companies/route.ts
import { NextResponse } from "next/server";
import { db, upsertCompany } from "../../data/b2b";

export async function GET(){
  return NextResponse.json({ ok:true, companies: db.companies });
}
export async function POST(req:Request){
  const body = await req.json().catch(()=>({}));
  if (!body || !body.id) return NextResponse.json({ ok:false, error:"missing_id" }, { status:400 });
  const tier = ["A","B","C"].includes(body.priceTier) ? body.priceTier : "A";
  const role = ["admin","ops","support","viewer"].includes(body.role) ? body.role : "viewer";
  return NextResponse.json({ ok:true, company: upsertCompany({
    id:String(body.id), name:String(body.name||body.id), priceTier:tier as any, role:role as any
  })});
}

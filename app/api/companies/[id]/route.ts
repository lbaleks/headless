// app/api/companies/[id]/route.ts
import { NextResponse } from "next/server";
import { db, upsertCompany } from "../../../data/b2b";

export async function GET(_:Request,{ params }:{ params:{ id:string } }){
  const c = db.companies.find(x=>x.id===params.id);
  return c ? NextResponse.json({ ok:true, company:c }) : NextResponse.json({ ok:false, error:"not_found" },{status:404});
}
export async function PUT(req:Request,{ params }:{ params:{ id:string } }){
  const body = await req.json().catch(()=>({}));
  return NextResponse.json({ ok:true, company: upsertCompany({ ...body, id:params.id }) });
}

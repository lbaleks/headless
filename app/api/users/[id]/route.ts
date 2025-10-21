export const runtime = 'nodejs';
// app/api/users/[id]/route.ts
import { NextResponse } from "next/server";
import { db, upsertUser } from "../../../data/b2b";

export async function GET(_:Request,{ params }:{ params:{ id:string } }){
  const u = db.users.find(x=>x.id===params.id);
  return u ? NextResponse.json({ ok:true, user:u }) : NextResponse.json({ ok:false, error:"not_found" },{status:404});
}
export async function PUT(req:Request,{ params }:{ params:{ id:string } }){
  const b = await req.json().catch(()=>({}));
  return NextResponse.json({ ok:true, user: upsertUser({ ...b, id:params.id }) });
}

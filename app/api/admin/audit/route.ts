// app/api/admin/audit/route.ts
import { NextResponse } from "next/server";
import { auditDB } from "@/app/data/audit";

export async function GET(){
  return NextResponse.json({ ok:true, events: auditDB.events });
}

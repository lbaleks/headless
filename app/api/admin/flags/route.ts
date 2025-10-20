// app/api/admin/flags/route.ts
import { NextResponse } from "next/server";
import { getFlags, setFlags, Flag } from "@/app/data/flags";

export async function GET() {
  return NextResponse.json({ ok:true, flags: getFlags() });
}

export async function PUT(req:Request) {
  const b = await req.json().catch(()=> ({}));
  const incoming = Array.isArray(b?.flags) ? b.flags : [];
  const clean:Flag[] = [];
  for (const f of incoming) {
    if (typeof f?.key === "string" && typeof f?.on === "boolean") {
      clean.push({ key:f.key, on:f.on, note: typeof f.note==="string" ? f.note : undefined } as Flag);
    }
  }
  if (clean.length===0) return NextResponse.json({ ok:false, error:"invalid_flags" }, { status:400 });
  return NextResponse.json({ ok:true, flags: setFlags(clean) });
}

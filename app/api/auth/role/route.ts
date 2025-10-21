export const runtime = 'nodejs';
// app/api/auth/role/route.ts
import { NextResponse } from "next/server";

function getRoleFromCookie(req: Request): string {
  const cookie = req.headers.get("cookie") || "";
  const m = cookie.match(/(?:^|;\s*)role=([^;]+)/);
  return m ? decodeURIComponent(m[1]) : "admin";
}

export async function GET(req: Request) {
  const role = getRoleFromCookie(req);
  return NextResponse.json({ ok: true, role });
}

export async function POST(req: Request) {
  const { role } = await req.json().catch(()=>({ role: "viewer" }));
  const r = NextResponse.json({ ok:true, role: role || "viewer" });
  r.headers.set("Set-Cookie", );
  return r;
}

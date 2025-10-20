// app/api/admin/orders/route.ts
import { NextResponse } from "next/server";
import { listOrders } from "../../../data/orders";

export async function GET(req:Request){
  try{
    const u = new URL(req.url);
    const q = u.searchParams.get("q") || "";
    const status = (u.searchParams.get("status") as any) || "all";
    const limit  = Number(u.searchParams.get("limit") || 50);
    const offset = Number(u.searchParams.get("offset") || 0);
    const { total, items } = listOrders({ q, status, limit, offset });
    return NextResponse.json({ ok:true, total, items });
  }catch(e:any){
    console.error("orders list error:", e);
    return NextResponse.json({ ok:false, error:e?.message||"list_failed", stack: e?.stack }, { status:500 });
  }
}

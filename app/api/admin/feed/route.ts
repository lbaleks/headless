import { NextResponse } from "next/server";

export async function GET() {
  const now = Date.now();
  return NextResponse.json({
    ok: true,
    generatedAt: now,
    kpi: {
      orders24h: 24,
      revenue7d: 71234,
      stockSync: "OK"
    },
    events: [
      { ts: now-1000*60*5,    type: "sync",   msg: "OMS sync completed (products 128, stock 431)" },
      { ts: now-1000*60*45,   type: "order",  msg: "New order #12031 (DK)" },
      { ts: now-1000*60*90,   type: "system", msg: "AI reco cache refreshed" }
    ]
  });
}

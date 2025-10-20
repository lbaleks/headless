// app/api/admin/kpis/route.ts
import { NextResponse } from "next/server";

export async function GET() {
  const cards = [
    { title: "Åpne ordre", value: 12, hint: "siden i går", tone: "ok" },
    { title: "Eksportkø", value: 3, hint: "venter på ERP", tone: "warn" },
    { title: "Feil siste 24t", value: 1, hint: "sjekk Orders Sync", tone: "bad" },
    { title: "Lavt lager", value: 2, hint: "< 10 base-enheter", tone: "warn" },
  ];
  const recent = [
    { id: "evt-1", kind: "order",   status: "queued",   label: "Ordre #10235 lagt i kø", ts: Date.now()-1000*60*8 },
    { id: "evt-2", kind: "export",  status: "exported", label: "Ordre #10212 eksportert", ts: Date.now()-1000*60*45 },
  ];
  return NextResponse.json({ ok: true, cards, recent });
}

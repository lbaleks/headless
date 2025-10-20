"use client";
import React from "react";
import Link from "next/link";
export default function RackbeatPage(){
  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h2 className="text-base font-medium">Rackbeat</h2>
        <div className="flex gap-2"><Link href="/admin/integrations">Tilbake</Link></div>
      </div>
      <section className="card"><div className="text-sm font-medium mb-1">Status</div><div className="sub">WMS/stock, innkjøp, plukk/pack – placeholder.</div></section>
      <section className="card"><div className="text-sm font-medium mb-2">Koblinger (placeholders)</div>
        <div className="grid-cards">
          <div className="card"><div className="text-sm font-medium">Autentisering</div><div className="sub">API-key – ikke satt</div><div style={{marginTop:".5rem"}}><button className="btn">Konfigurer</button></div></div>
          <div className="card"><div className="text-sm font-medium">Lager</div><div className="sub">Lokasjoner, batch/lot</div><div style={{marginTop:".5rem"}}><button className="btn">Åpne oppsett</button></div></div>
          <div className="card"><div className="text-sm font-medium">Plukk/Pack</div><div className="sub">Workflows og status</div><div style={{marginTop:".5rem"}}><button className="btn">Kjør nå</button></div></div>
        </div>
      </section>
      <section className="card"><div className="text-sm font-medium mb-2">Hendelser</div><div className="sub">Kommer: feed, feil og retry</div></section>
    </div>
  );
}

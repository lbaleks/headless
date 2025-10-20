import { NextResponse } from "next/server";
import fs from "fs";
import path from "path";

const storePath = path.join(process.cwd(), "tmp_drafts.json");
const gateway = process.env.NEXT_PUBLIC_GATEWAY_BASE || "http://localhost:3044";

function readAll(): any[] {
  return fs.existsSync(storePath) ? JSON.parse(fs.readFileSync(storePath, "utf8")) : [];
}
function writeAll(a: any[]) {
  fs.writeFileSync(storePath, JSON.stringify(a, null, 2));
}

async function sendToMagento(d: any) {
  try {
    const resp = await fetch(`${gateway}/ops/product/draft`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        name: d.name,
        description: d.description,
        attributes: d.attributes || {},
        price: ((d.attributes?.abv || 0) * 10 + 49),
        stock: Math.max(20, 100 - (d.attributes?.ibu || 10)),
        sku: d.name.replace(/[^a-z0-9-]/gi, "_").toUpperCase(),
      }),
    });
    const j = await resp.json();
    return j.ok ? j : { ok: false, error: j.error || "gateway_error" };
  } catch (e: any) {
    return { ok: false, error: e?.message || "network_error" };
  }
}

export async function GET() {
  return NextResponse.json({ ok: true, lite: "op-ok" });
}

export async function POST() {
  try {
    const all = readAll();
    let count = 0;
    for (const d of all.filter((x: any) => !x.synced)) {
      const r = await sendToMagento(d);
      if (r.ok) {
        d.synced = true;
        d.magentoId = r.id || Math.floor(Math.random() * 900000);
        d.syncedAt = new Date().toISOString();
        count++;
      } else {
        console.error("❗ Sync-feil:", d.name, r.error);
      }
    }
    writeAll(all);
    return NextResponse.json({ ok: true, synced: count });
  } catch (e: any) {
    return NextResponse.json({ ok: false, error: e?.message || "sync_failed" }, { status: 500 });
  }
}

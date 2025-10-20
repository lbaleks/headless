#!/usr/bin/env bash
set -euo pipefail

echo "➡️  Installerer admin-UI for configurable-link + pris…"

ADMIN_DIR="$(find "$HOME/Documents/M2" -type d -name admstage | head -n1)"
[ -d "$ADMIN_DIR" ] || { echo "❌ Fant ikke admstage"; exit 1; }

# Sørg for gateway-base i .env.local (bruker localhost:3044)
ENVFILE="$ADMIN_DIR/.env.local"
touch "$ENVFILE"
awk -v val="http://localhost:3044" '
  BEGIN{FS="=";OFS="="}
  $1=="NEXT_PUBLIC_GATEWAY_BASE"{print "NEXT_PUBLIC_GATEWAY_BASE",val; seen=1; next}
  {print}
  END{ if(!seen) print "NEXT_PUBLIC_GATEWAY_BASE",val }
' "$ENVFILE" > "$ENVFILE.tmp" && mv "$ENVFILE.tmp" "$ENVFILE"

mkdir -p "$ADMIN_DIR/app/m2/configurable" "$ADMIN_DIR/app/m2/price"

# configurable/page.tsx
cat > "$ADMIN_DIR/app/m2/configurable/page.tsx" <<'TSX'
"use client";
import { useState } from "react";
import Link from "next/link";
import { api } from "@/lib/api";

export default function LinkConfigurablePage() {
  const [parentSku, setParentSku] = useState("TEST-CFG");
  const [childSku, setChildSku] = useState("TEST-BLUE-EXTRA");
  const [attrCode, setAttrCode] = useState("cfg_color");
  const [valueIndex, setValueIndex] = useState("7");
  const [log, setLog] = useState<string>("");

  const linkIt = async () => {
    setLog("⏳ sender…");
    try {
      const body = { parentSku, childSku, attrCode, valueIndex: Number(valueIndex) };
      const data = await api.post("/ops/configurable/link", body);
      setLog(JSON.stringify(data, null, 2));
    } catch (e: any) {
      setLog("❌ " + (e?.message || String(e)));
    }
  };

  return (
    <div className="p-6 space-y-4">
      <h1 className="text-2xl font-bold">🔗 Link configurable</h1>
      <div className="flex gap-2">
        <Link href="/m2" className="px-3 py-2 rounded-lg border hover:bg-black/5">← Hjem</Link>
        <Link href="/m2/price" className="px-3 py-2 rounded-lg border hover:bg-black/5">Pris</Link>
      </div>

      <div className="grid gap-3 max-w-lg">
        <label className="block">
          <div className="text-sm">Parent SKU</div>
          <input className="border rounded-lg px-3 py-2 w-full" value={parentSku} onChange={e=>setParentSku(e.target.value)} />
        </label>
        <label className="block">
          <div className="text-sm">Child SKU</div>
          <input className="border rounded-lg px-3 py-2 w-full" value={childSku} onChange={e=>setChildSku(e.target.value)} />
        </label>
        <label className="block">
          <div className="text-sm">Attributt (attrCode)</div>
          <input className="border rounded-lg px-3 py-2 w-full" value={attrCode} onChange={e=>setAttrCode(e.target.value)} />
        </label>
        <label className="block">
          <div className="text-sm">Value index</div>
          <input className="border rounded-lg px-3 py-2 w-full" value={valueIndex} onChange={e=>setValueIndex(e.target.value)} />
        </label>

        <button onClick={linkIt} className="px-3 py-2 rounded-lg border hover:bg-black/5">
          Link child → parent
        </button>

        <pre className="text-xs bg-black/5 p-3 rounded max-h-64 overflow-auto">{log}</pre>
      </div>
    </div>
  );
}
TSX

# price/page.tsx
cat > "$ADMIN_DIR/app/m2/price/page.tsx" <<'TSX'
"use client";
import { useState } from "react";
import Link from "next/link";
import { api } from "@/lib/api";

export default function PricePage() {
  const [sku, setSku] = useState("TEST-BLUE-EXTRA");
  const [price, setPrice] = useState("199.00");
  const [log, setLog] = useState<string>("");

  const save = async () => {
    setLog("⏳ sender…");
    try {
      const body = { sku, price: Number(price) };
      const data = await api.post("/ops/price/upsert", body);
      setLog(JSON.stringify(data, null, 2));
    } catch (e: any) {
      setLog("❌ " + (e?.message || String(e)));
    }
  };

  return (
    <div className="p-6 space-y-4">
      <h1 className="text-2xl font-bold">💶 Sett pris</h1>
      <div className="flex gap-2">
        <Link href="/m2" className="px-3 py-2 rounded-lg border hover:bg-black/5">← Hjem</Link>
        <Link href="/m2/configurable" className="px-3 py-2 rounded-lg border hover:bg-black/5">Configurable</Link>
      </div>

      <div className="grid gap-3 max-w-lg">
        <label className="block">
          <div className="text-sm">SKU</div>
          <input className="border rounded-lg px-3 py-2 w-full" value={sku} onChange={e=>setSku(e.target.value)} />
        </label>
        <label className="block">
          <div className="text-sm">Pris</div>
          <input className="border rounded-lg px-3 py-2 w-full" value={price} onChange={e=>setPrice(e.target.value)} />
        </label>

        <button onClick={save} className="px-3 py-2 rounded-lg border hover:bg-black/5">
          Lagre pris
        </button>

        <pre className="text-xs bg-black/5 p-3 rounded max-h-64 overflow-auto">{log}</pre>
      </div>
    </div>
  );
}
TSX

echo "✅ Skrev:"
echo "  - $ADMIN_DIR/app/m2/configurable/page.tsx"
echo "  - $ADMIN_DIR/app/m2/price/page.tsx"
echo "➡️  Start/refresh admstage på http://localhost:3000"
echo "   /m2/configurable  og  /m2/price"

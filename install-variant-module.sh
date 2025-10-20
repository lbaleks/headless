#!/usr/bin/env bash
set -euo pipefail

echo "➡️  Installerer variantmodul…"

GATEWAY_DIR="$(find "$HOME/Documents/M2" -type d -name m2-gateway | head -n1)"
ADMIN_DIR="$(find "$HOME/Documents/M2" -type d -name admstage | head -n1)"
[ -d "$GATEWAY_DIR" ] || { echo "❌ Fant ikke m2-gateway"; exit 1; }
[ -d "$ADMIN_DIR" ] || { echo "❌ Fant ikke admstage"; exit 1; }

##########################################
# GATEWAY
##########################################
cat > "$GATEWAY_DIR/routes-variants.js" <<'JS'
import express from "express";
import fetch from "node-fetch";
export default function (app) {
  const router = express.Router();

  // POST /ops/variant/heal - proxy rett gjennom
  router.post("/heal", async (req, res) => {
    try {
      const base = process.env.MAGENTO_BASE;
      const token = process.env.MAGENTO_TOKEN;
      const url = \`\${base}/rest/V1/litebrygg/ops/variant/heal\`;
      const response = await fetch(url, {
        method: "POST",
        headers: { "Authorization": token, "Content-Type": "application/json" },
        body: JSON.stringify(req.body),
      });
      const data = await response.json();
      res.json(data);
    } catch (err) {
      res.status(500).json({ ok: false, error: String(err) });
    }
  });

  app.use("/ops/variant", router);
}
JS

# Patch server.js
perl -0777 -pe 's|(require\(\s*["'\'']\.\/routes-products["'\'']\)\(app\)\s*;)|\1\nrequire("./routes-variants")(app);|' -i "$GATEWAY_DIR/server.js"

##########################################
# ADMIN
##########################################
mkdir -p "$ADMIN_DIR/app/m2/variants"

cat > "$ADMIN_DIR/app/m2/variants/page.tsx" <<'TSX'
"use client";
import { useState } from "react";
import Link from "next/link";
import { api } from "@/lib/api";

export default function VariantsPage() {
  const [parentSku, setParentSku] = useState("TEST-CFG");
  const [sku, setSku] = useState("TEST-BLUE-EXTRA");
  const [cfgAttr, setCfgAttr] = useState("cfg_color");
  const [cfgValue, setCfgValue] = useState("7");
  const [label, setLabel] = useState("Blue");
  const [log, setLog] = useState<string>("");

  const heal = async () => {
    setLog("⏳ sender…");
    try {
      const body = {
        parentSku,
        sku,
        cfgAttr,
        cfgValue: Number(cfgValue),
        label,
        websiteId: 1,
        stock: { source_code: "default", quantity: 5, status: 1 },
      };
      const data = await api.post("/ops/variant/heal", body);
      setLog(JSON.stringify(data, null, 2));
    } catch (e: any) {
      setLog("❌ " + e.message);
    }
  };

  return (
    <div className="p-6 space-y-4">
      <h1 className="text-2xl font-bold">🧩 Variant-healer</h1>
      <div className="flex gap-2">
        <Link href="/m2" className="px-3 py-2 rounded-lg border hover:bg-black/5">← Hjem</Link>
      </div>

      <div className="grid gap-3 max-w-lg">
        <label className="block">
          <div className="text-sm">Parent SKU</div>
          <input className="border rounded-lg px-3 py-2 w-full" value={parentSku} onChange={e=>setParentSku(e.target.value)} />
        </label>

        <label className="block">
          <div className="text-sm">Variant SKU</div>
          <input className="border rounded-lg px-3 py-2 w-full" value={sku} onChange={e=>setSku(e.target.value)} />
        </label>

        <label className="block">
          <div className="text-sm">Konfigurasjonsattributt</div>
          <input className="border rounded-lg px-3 py-2 w-full" value={cfgAttr} onChange={e=>setCfgAttr(e.target.value)} />
        </label>

        <label className="block">
          <div className="text-sm">Verdi (id)</div>
          <input className="border rounded-lg px-3 py-2 w-full" value={cfgValue} onChange={e=>setCfgValue(e.target.value)} />
        </label>

        <label className="block">
          <div className="text-sm">Label</div>
          <input className="border rounded-lg px-3 py-2 w-full" value={label} onChange={e=>setLabel(e.target.value)} />
        </label>

        <button onClick={heal} className="px-3 py-2 rounded-lg border hover:bg-black/5">
          Heal / opprett variant
        </button>

        <pre className="text-xs bg-black/5 p-3 rounded max-h-64 overflow-auto">{log}</pre>
      </div>
    </div>
  );
}
TSX

##########################################
# Restart hint
##########################################
echo "✅ Variantmodul installert!"
echo "➡️  Gateway: $GATEWAY_DIR (restart: pkill -f 'node server.js' && node server.js)"
echo "➡️  Admin-side: http://localhost:3000/m2/variants"

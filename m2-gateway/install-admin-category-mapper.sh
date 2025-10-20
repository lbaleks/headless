#!/usr/bin/env bash
set -euo pipefail

ADMIN_DIR="$(find "$HOME/Documents/M2" -type d -name "admstage" -print -quit)"
GATEWAY_PORT=3044

echo "➡️  Admin:   $ADMIN_DIR"
echo "➡️  Gateway: http://localhost:${GATEWAY_PORT}"

# Sørg for at .env.local finnes
grep -q "NEXT_PUBLIC_GATEWAY_BASE" "$ADMIN_DIR/.env.local" 2>/dev/null || {
  echo "NEXT_PUBLIC_GATEWAY_BASE=http://localhost:${GATEWAY_PORT}" >> "$ADMIN_DIR/.env.local"
}

# Skriv ny admin-side
cat > "$ADMIN_DIR/app/m2/categories/page.tsx" <<'JSX'
"use client";
import { useState } from "react";
import axios from "axios";

export default function CategoryMapper() {
  const [sku, setSku] = useState("");
  const [cats, setCats] = useState("");
  const [result, setResult] = useState<any>(null);
  const base = process.env.NEXT_PUBLIC_GATEWAY_BASE || "http://localhost:3044";

  const handleSubmit = async () => {
    try {
      const ids = cats.split(",").map((x) => parseInt(x.trim())).filter((x) => !isNaN(x));
      const res = await axios.post(\`\${base}/ops/category/replace\`, {
        items: [{ sku, categoryIds: ids }],
      });
      setResult(res.data);
    } catch (err: any) {
      setResult({ error: err.message });
    }
  };

  return (
    <main className="p-8 max-w-xl mx-auto space-y-6">
      <h1 className="text-2xl font-bold">🧩 Category Mapper</h1>
      <div className="space-y-4">
        <div>
          <label className="block text-sm font-medium">SKU</label>
          <input
            value={sku}
            onChange={(e) => setSku(e.target.value)}
            placeholder="f.eks. TEST-RED"
            className="border p-2 w-full rounded-md"
          />
        </div>
        <div>
          <label className="block text-sm font-medium">Category IDs (kommaseparert)</label>
          <input
            value={cats}
            onChange={(e) => setCats(e.target.value)}
            placeholder="2,4,7"
            className="border p-2 w-full rounded-md"
          />
        </div>
        <button
          onClick={handleSubmit}
          className="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-md"
        >
          Oppdater kategorier
        </button>
      </div>

      {result && (
        <pre className="bg-gray-900 text-green-400 p-3 rounded-lg text-sm overflow-x-auto">
          {JSON.stringify(result, null, 2)}
        </pre>
      )}

      <div className="text-xs text-gray-400 mt-4">
        Gateway: {base}
      </div>
    </main>
  );
}
JSX

echo "✅ Skrev: $ADMIN_DIR/app/m2/categories/page.tsx"
echo "➡️  Start admin og åpne: http://localhost:3000/m2/categories"

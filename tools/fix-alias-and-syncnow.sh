#!/bin/bash
set -euo pipefail

# 1) Ensure @ → src alias is configured
node -e '
const fs = require("fs");
if (fs.existsSync("tsconfig.json")) {
  const p = "tsconfig.json";
  const j = JSON.parse(fs.readFileSync(p,"utf8"));
  j.compilerOptions ||= {};
  j.compilerOptions.baseUrl = ".";
  // IMPORTANT: only one wildcard for Next 15 (no "@/*": ["src/*","something/*"])
  j.compilerOptions.paths = { "@/*": ["src/*"] };
  fs.writeFileSync(p, JSON.stringify(j, null, 2));
  console.log("✓ Patched tsconfig.json with paths { \"@/*\": [\"src/*\"] }");
} else {
  const p = "jsconfig.json";
  const j = { compilerOptions: { baseUrl: ".", paths: { "@/*": ["src/*"] } } };
  fs.writeFileSync(p, JSON.stringify(j, null, 2));
  console.log("✓ Created jsconfig.json with paths { \"@/*\": [\"src/*\"] }");
}
'

# 2) Create a minimal SyncNowMini component if it doesn't exist
mkdir -p src/components
if [ ! -f src/components/SyncNowMini.tsx ]; then
  cat > src/components/SyncNowMini.tsx <<'TSX'
"use client";
import React from "react";

export default function SyncNowMini() {
  const onClick = async () => {
    try {
      await fetch("/api/orders/sync/", { method: "POST" });
      alert("Sync trigget!");
    } catch {
      alert("Klarte ikke trigge sync");
    }
  };
  return (
    <button
      type="button"
      onClick={onClick}
      className="px-3 py-1 rounded border text-sm hover:bg-black/5"
      aria-label="Sync nå"
    >
      Sync nå
    </button>
  );
}
TSX
  echo "✓ Added stub: src/components/SyncNowMini.tsx"
else
  echo "• Found existing src/components/SyncNowMini.tsx (left untouched)"
fi

echo "✅ Alias + component ready. If dev server is running, restart it so Next picks up tsconfig changes."

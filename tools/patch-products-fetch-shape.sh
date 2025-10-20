#!/usr/bin/env bash
set -euo pipefail
FILE="app/admin/products/page.tsx"
test -f "$FILE" || { echo "Finner ikke $FILE"; exit 1; }

# 1) Legg inn fleksibel parsing ved første fetch
perl -0777 -i -pe '
s/const \{ data, error \} = await safeFetchJSON<Product\[]>\x28\'\/api\/products\?page=1\&size=200\'\x29\s*?\n\s*if \(!mounted\) return\n\s*if \(error\) setError\(error\)\n\s*setRows\(Array\.isArray\(data\) \? data : \[\]\)/
const res = await fetch("\/api\/products?page=1&size=200",{cache:"no-store"});
let data:any = [];
let error: string | undefined = undefined;
try {
  if (!res.ok) { error = `HTTP ${res.status}` }
  const raw = await res.json();
  data = Array.isArray(raw) ? raw : (raw?.items ?? raw?.data ?? []);
} catch(e:any){ error = e?.message || "Ukjent feil" }
if (!mounted) return
if (error) setError(error)
setRows(Array.isArray(data) ? data : [])
/s' "$FILE"

# 2) Fallback dersom importen av AdminPage mangler riktig sti
perl -0777 -i -pe 's#\{ AdminPage \} from .+AdminPage.+#\{ AdminPage \} from "@/src/components/AdminPage"#' "$FILE"

echo "→ Rydder .next-cache"
rm -rf .next .next-cache 2>/dev/null || true
echo "✓ Patch OK. Start dev-server på nytt (npm run dev)."
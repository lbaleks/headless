#!/usr/bin/env bash
set -euo pipefail
FILE="app/api/orders/route.ts"

if [ ! -f "$FILE" ]; then
  echo "❌ Finner ikke $FILE"; exit 1
fi

cp "$FILE" "$FILE.bak.$(date +%s)" || true

python3 - "$FILE" <<'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text()

# Bytt ut catch-blokka i GET som kaller serverError(...)
# med en soft-fail som returnerer tom liste.
pat = re.compile(
    r"\}\s*catch\s*\(\s*err:any\s*\)\s*\{\s*return\s+serverError\([^}]*\)\s*\}",
    re.S
)

def repl(_):
    return (
        "} catch (err:any) {\n"
        "  // Soft-fail: returner tom liste istedenfor 500 når Magento feiler\n"
        "  return NextResponse.json({ total: 0, items: [], warn: String((err as any)?.message ?? String(err)) })\n"
        "}\n"
    )

new, n = pat.subn(repl, t, count=1)
if n == 0:
    print('⚠️  Fant ikke forventet catch(serverError(...)) i GET. Ingen endring gjort.')
else:
    p.write_text(new)
    print(f'✓ Patchet GET-catch i {p}')
PY

# Rydd Next-cache
rm -rf .next .next-cache 2>/dev/null || true
echo "✓ Ferdig. Start dev på nytt: npm run dev"

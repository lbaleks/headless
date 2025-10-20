#!/usr/bin/env bash
set -euo pipefail

log(){ echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

BASE=${BASE:-http://localhost:3000}

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' må være installert"; exit 1; }; }
need jq
need node
need npm

log "Starter hardening…"

# 0) Sørg for mappestruktur og tsconfig-paths
mkdir -p src/components/admin
if [ -f tsconfig.json ]; then
  tmp=$(mktemp)
  jq '
    .compilerOptions = (.compilerOptions // {}) |
    .compilerOptions.paths = (.compilerOptions.paths // {}) |
    .compilerOptions.paths["*@/*"] = (.compilerOptions.paths["*@/*"] // ["*"])
  ' tsconfig.json > "$tmp" && mv "$tmp" tsconfig.json
  log "Tsconfig paths OK"
fi

# 1) Husky + lint-staged (idempotent)
log "Setter opp Husky + lint-staged"
if ! grep -q '"lint-staged"' package.json 2>/dev/null; then
  tmp=$(mktemp)
  jq '. + { "lint-staged": { "*.{ts,tsx,js,jsx}": ["eslint --fix"] } }' package.json > "$tmp" && mv "$tmp" package.json
  log "La til lint-staged i package.json"
else
  log "lint-staged finnes fra før (ok)"
fi

if [ ! -d ".husky" ]; then
  npx husky init >/dev/null 2>&1 || true
  log "Initialiserte Husky"
fi
mkdir -p .husky
if [ ! -f ".husky/pre-commit" ]; then
  cat > .husky/pre-commit <<'HOOK'
#!/usr/bin/env sh
. "$(dirname "$0")/_/husky.sh"
npx lint-staged
HOOK
  chmod +x .husky/pre-commit
  log "Opprettet .husky/pre-commit"
else
  grep -q 'lint-staged' .husky/pre-commit || { echo 'npx lint-staged' >> .husky/pre-commit; chmod +x .husky/pre-commit; log "Oppdaterte pre-commit"; }
fi

# 2) verify-essentials
log "Skriver tools/verify-essentials.sh"
mkdir -p tools
cat > tools/verify-essentials.sh <<'VSH'
#!/usr/bin/env bash
set -euo pipefail
BASE=${BASE:-http://localhost:3000}
say(){ printf "%s\n" "$*"; }
say "→ Health";           curl -fsS "$BASE/api/debug/health" | jq '.ok'
say "→ Single completeness"; curl -fsS "$BASE/api/products/completeness?sku=TEST" | jq '{sku:(.items[0].sku),family:(.items[0].family),score:(.items[0].completeness.score)}'
say "→ Attributes";       curl -fsS "$BASE/api/products/attributes/TEST" | jq .
VSH
chmod +x tools/verify-essentials.sh

# 3) NPM-scripts
log "Oppdaterer package.json scripts"
tmp=$(mktemp)
jq '
  .scripts = (.scripts // {}) |
  .scripts["verify:essentials"] = "BASE=${BASE:-http://localhost:3000} bash tools/verify-essentials.sh"
' package.json > "$tmp" && mv "$tmp" package.json

# 4) Manglende admin-komponenter (stub-er) for å fjerne "Module not found"
if [ ! -f src/components/admin/SyncButtons.tsx ]; then
  cat > src/components/admin/SyncButtons.tsx <<'TSX'
"use client";
import { useState } from "react";

export default function SyncButtons() {
  const [busy, setBusy] = useState(false);
  const [last, setLast] = useState<string | null>(null);

  async function run() {
    try {
      setBusy(true);
      const r = await fetch("/api/jobs/run-sync", { method: "POST" });
      const j = await r.json();
      setLast(j?.id ?? "OK");
    } catch (e) {
      setLast("error");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex items-center gap-2">
      <button
        onClick={run}
        disabled={busy}
        className="px-3 py-1 rounded bg-black text-white disabled:opacity-50"
      >
        {busy ? "Syncing…" : "Sync now"}
      </button>
      {last && <span className="text-xs text-neutral-600">Last: {last}</span>}
    </div>
  );
}
TSX
  log "Opprettet src/components/admin/SyncButtons.tsx"
else
  log "SyncButtons.tsx finnes (ok)"
fi

if [ ! -f src/components/admin/DevOpsBar.tsx ]; then
  cat > src/components/admin/DevOpsBar.tsx <<'TSX'
"use client";
import useSWR from "swr";
const fetcher = (u:string) => fetch(u).then(r=>r.json());

export default function DevOpsBar(){
  const { data } = useSWR("/api/jobs/latest", fetcher);
  const id = data?.item?.id ?? "—";
  return (
    <div className="text-xs text-neutral-600">
      Last job: <span className="font-mono">{id}</span>
    </div>
  );
}
TSX
  log "Opprettet src/components/admin/DevOpsBar.tsx"
else
  log "DevOpsBar.tsx finnes (ok)"
fi

# 5) Warm-up & verify
log "Rask warm-up"
curl -fsS "$BASE/api/debug/health" >/dev/null || true
curl -fsS "$BASE/api/products/merged?page=1&size=1" >/dev/null || true

log "Kjører verify:essentials"
npm run --silent verify:essentials || { echo "⚠ verify:essentials feilet"; exit 1; }

log "Hardening ferdig ✅"

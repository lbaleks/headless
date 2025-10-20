#!/usr/bin/env bash
set -euo pipefail

log(){ printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# --- 1) Normaliser dynamiske mapper: [id] -> [sku] for ALLE .../products/*
log "1) Normaliserer dynamiske mapper: [id] -> [sku]"
find app -type d -path '*/products/[id]' 2>/dev/null | while IFS= read -r d; do
  parent="$(dirname "$d")"
  tgt="$parent/[sku]"
  log "→ $d  ->  $tgt"
  mkdir -p "$tgt"
  # Flytt/kopier filer uten å overskrive eksisterende i [sku]
  find "$d" -type f -maxdepth 1 -print0 | while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    [ -f "$tgt/$base" ] || mv "$f" "$tgt/$base"
  done
  rm -rf "$d"
done

# --- 2) Patch params.id -> params.sku og typer i alle filer under products
log "2) Patcher params.id -> params.sku og typer"
find app -type f -path '*/products/*' \( -name '*.ts' -o -name '*.tsx' \) -print0 \
| while IFS= read -r -d '' f; do
  # macOS/BSD sed
  sed -i '' -E 's/\bparams\.id\b/params.sku/g' "$f"
  sed -i '' -E 's/\bparams:\s*\{\s*id:\s*string\s*\}/params: { sku: string }/g' "$f"
  sed -i '' -E 's/\bparams:\s*\{\s*id:\s*[A-Za-z_][A-Za-z0-9_]*\s*\}/params: { sku: string }/g' "$f"
done

# --- 3) I attributes-API: behold kun [sku]
log "3) Rydder dynamiske mapper i attributes-API (behold kun [sku])"
if [ -d "app/api/products/attributes" ]; then
  find app/api/products/attributes -maxdepth 1 -type d -regex '.*/\[[^]]+\]' -print \
  | while IFS= read -r d; do
      case "$d" in
        */[sku]) : ;; # behold
        *) log "   • Fjerner $d (kolliderer)"; rm -rf "$d" ;;
      esac
    done
fi

# --- 4) Tøm Next cache og restart dev
log "4) Tømmer .next, frigjør :3000 og restarter dev"
rm -rf .next
lsof -ti :3000 2>/dev/null | xargs -r kill -9 2>/dev/null || true
# kjør i bakgrunnen
npm run dev --silent >/dev/null 2>&1 &

# --- 5) Vent til server er oppe
BASE=${BASE:-http://localhost:3000}
log "5) Venter på at dev-server svarer (${BASE}) ..."
deadline=$((SECONDS+30))
ok=0
while [ $SECONDS -lt $deadline ]; do
  if curl -fsS "$BASE/api/debug/health" >/dev/null 2>&1; then ok=1; break; fi
  # fallback: ping en lett route hvis health mangler
  if curl -fsS "$BASE/api/jobs" >/dev/null 2>&1; then ok=1; break; fi
  sleep 1
done
if [ "$ok" -eq 1 ]; then
  log "   • Server OK"
else
  log "   • Server ikke verifisert (fortsetter likevel)"
fi

# --- 6) Smoke-tester attributes endepunkt
log "6) Røyk-test: attributes (dynamisk + fallback)"
code=$(curl -sS -D- "$BASE/api/products/attributes/TEST" -o /tmp/attr.json | awk 'NR==1{print $2}')
mime=$(file -b --mime-type /tmp/attr.json 2>/dev/null || true)
log "   • /attributes/TEST -> HTTP $code, mime=${mime:-unknown}"
head -c 200 /tmp/attr.json 2>/dev/null && echo || true

code2=$(curl -sS -o /dev/null -w "%{http_code}" "$BASE/api/products/attributes?sku=TEST" || true)
log "   • /attributes?sku=TEST -> HTTP $code2"

log "Ferdig ✅"
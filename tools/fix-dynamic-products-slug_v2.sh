# tools/fix-dynamic-products-slug_v2.sh
#!/usr/bin/env bash
set -euo pipefail

log(){ printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# --- 1) Finn og normaliser alle .../products/[id] -> .../products/[sku]
log "1) Normaliserer dynamiske mapper: [id] -> [sku]"
find app -type d -path '*/products/[id]' 2>/dev/null | while IFS= read -r d; do
  tgt="$(dirname "$d")/[sku]"
  log "→ $d  ->  $tgt"
  mkdir -p "$tgt"
  # Kopier filer hvis de ikke allerede finnes i [sku]
  find "$d" -type f -maxdepth 1 -print0 | while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    [ -f "$tgt/$base" ] || cp -p "$f" "$tgt/$base"
  done
  rm -rf "$d"
done

# --- 2) Patch filer under products/ som bruker params.id
log "2) Patcher params.id -> params.sku og typer"
# Finn alle .ts/.tsx under en products/-sti
find app -type f -path '*/products/*' \( -name '*.ts' -o -name '*.tsx' \) -print0 \
| while IFS= read -r -d '' f; do
  # macOS/BSD sed krever -i ''
  sed -i '' -E 's/\bparams\.id\b/params.sku/g' "$f"
  sed -i '' -E 's/\bparams:\s*\{\s*id:\s*string\s*\}/params: { sku: string }/g' "$f"
  sed -i '' -E 's/\bparams:\s*\{\s*id:\s*[A-Za-z_][A-Za-z0-9_]*\s*\}/params: { sku: string }/g' "$f"
done

# --- 3) I attributes-API: sørg for at KUN [sku] finnes
log "3) Rydder eventuelle flere dynamiske mapper i attributes-API"
if [ -d "app/api/products/attributes" ]; then
  find app/api/products/attributes -maxdepth 1 -type d -regex '.*/\[[^]]+\]' -print \
  | while IFS= read -r d; do
      case "$d" in
        */[sku]) : ;; # behold
        *) log "   • Fjerner $d (kolliderer)"; rm -rf "$d" ;;
      esac
    done
fi

# --- 4) Tøm cache og restart dev
log "4) Tømmer .next og restarter dev"
rm -rf .next
lsof -ti :3000 2>/dev/null | xargs -r kill -9 2>/dev/null || true
npm run dev --silent >/dev/null 2>&1 & sleep 1

# --- 5) Røyk-test
BASE=${BASE:-http://localhost:3000}
log "5) Røyk-test"
if curl -sS "$BASE/api/debug/health" >/dev/null 2>&1; then
  log "   • Health OK"
else
  log "   • Health ikke tilgjengelig (ok)"
fi

# Test attributes-API (dynamisk path)
if curl -sS -D- "$BASE/api/products/attributes/TEST" -o /tmp/attr.json | head -n1; then
  file -b --mime-type /tmp/attr.json 2>/dev/null || true
  head -c 200 /tmp/attr.json 2>/dev/null && echo || true
fi

log "Ferdig ✅"
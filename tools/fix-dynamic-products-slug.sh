# tools/fix-dynamic-products-slug.sh
#!/usr/bin/env bash
set -euo pipefail

log(){ printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

log "1) Finn mapper som kolliderer (products/[id])"
mapfile -t ID_DIRS < <(find app -type d -path '*/products/[id]' 2>/dev/null || true)
if ((${#ID_DIRS[@]})); then
  for d in "${ID_DIRS[@]}"; do
    tgt="$(dirname "$d")/[sku]"
    log "→ Normaliserer: $d  ->  $tgt"
    mkdir -p "$tgt"
    rsync -a "$d/." "$tgt/" || true
    rm -rf "$d"
  done
else
  log "Ingen products/[id] funnet (bra)."
fi

log "2) Patch filer som forventer params.id → params.sku"
# Bare i filer under en products/ sti
mapfile -t FILES < <(git ls-files -z -- 'app/**/products/**.ts*' 2>/dev/null \
                  | xargs -0 -I{} echo "{}" || true)
# Fallback uten git ls-files
if [ ${#FILES[@]} -eq 0 ]; then
  mapfile -t FILES < <(find app -type f -path '*/products/*' \( -name '*.ts' -o -name '*.tsx' \))
fi

for f in "${FILES[@]}"; do
  # macOS/BSD sed
  sed -i '' -E 's/\bparams\.id\b/params.sku/g' "$f"
  sed -i '' -E 's/\bparams:\s*\{\s*id:\s*string\s*\}/params: { sku: string }/g' "$f"
  sed -i '' -E 's/\bparams:\s*\{\s*id:\s*\w+\s*\}/params: { sku: string }/g' "$f"
done

log "3) Sjekk for andre dynamiske products-segmenter med annen slug"
# Dette lister ev. resterende produkter segment-slugger
find app -type d -regex '.*/products/\[[^]]+\]' -print

log "4) Tøm Next-cache og restart dev"
rm -rf .next
lsof -ti :3000 2>/dev/null | xargs -r kill -9 2>/dev/null || true
npm run dev --silent >/dev/null 2>&1 & sleep 1

log "5) Hurtig verifisering"
BASE=${BASE:-http://localhost:3000}
curl -sS "$BASE/api/debug/health" >/dev/null 2>&1 && log "Health OK" || log "::INFO:: Health ikke funnet (ok)."

# Sjekk at admin-detaljsiden bygger (bare HTTP 200 på /admin er nok som røyk)
curl -sS -D- "$BASE/admin" -o /dev/null | head -n1 || true

# API som bruker products/[sku] bør nå være grønn
curl -sS -D- "$BASE/api/products/attributes/TEST" -o /tmp/attr.json | head -n1 || true
file -b --mime-type /tmp/attr.json 2>/dev/null || true
head -c 200 /tmp/attr.json 2>/dev/null && echo || true

log "Ferdig ✅  (hvis dev fortsatt klager: kjør 'npm run dev' i forgrunn og del første feilmelding)"
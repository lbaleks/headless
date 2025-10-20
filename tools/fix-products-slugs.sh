#!/usr/bin/env bash
set -euo pipefail

log(){ printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# Move+merge: flytt alle filer fra SRC til DST, men ikke overskriv eksisterende
move_merge() {
  local SRC="$1" DST="$2"
  [ -d "$SRC" ] || return 0
  mkdir -p "$DST"
  find "$SRC" -maxdepth 1 -type f -print0 | while IFS= read -r -d '' f; do
    local base="$(basename "$f")"
    if [ -e "$DST/$base" ]; then
      log "• Beholder eksisterende $DST/$base (hopper over $base i $(basename "$SRC"))"
    else
      mv "$f" "$DST/$base"
      log "• Flyttet $SRC/$base → $DST/$base"
    fi
  done
  # flytt undermapper hvis noen (kanttilfelle)
  find "$SRC" -mindepth 1 -type d -print0 | while IFS= read -r -d '' d; do
    local sub="$(basename "$d")"
    if [ -e "$DST/$sub" ]; then
      log "• Undermappe finnes allerede: $DST/$sub (hopper over $sub)"
    else
      mv "$d" "$DST/$sub"
      log "• Flyttet mappe $SRC/$sub → $DST/$sub"
    fi
  done
  rm -rf "$SRC"
}

# 1) Normaliser dynamiske mapper i admin og api
for ROOT in app/admin/products app/api/products; do
  if [ -d "$ROOT/[id]" ]; then
    log "Normaliserer: $ROOT/[id] → $ROOT/[sku]"
    move_merge "$ROOT/[id]" "$ROOT/[sku]"
  fi
done

# 2) Rydd eventuelle ekstra dynamiske varianter i attributes-API (behold kun [sku])
if [ -d "app/api/products/attributes" ]; then
  log "Rydder dynamiske mapper i attributes-API (behold kun [sku])"
  find app/api/products/attributes -maxdepth 1 -type d -name '[[]*[]]' ! -name '[sku]' -exec rm -rf {} +
  mkdir -p app/api/products/attributes/[sku]
fi

# 3) Patcher kode: params.id -> params.sku, og typer
patch_glob() {
  local DIR="$1"
  [ -d "$DIR" ] || return 0
  # macOS/BSD sed: -i ''
  find "$DIR" -type f \( -name '*.ts' -o -name '*.tsx' \) -print0 | xargs -0 sed -i '' -E \
    -e 's/\bparams\.id\b/params.sku/g' \
    -e 's/params:\s*\{\s*id:\s*string\s*\}/params: { sku: string }/g' \
    -e 's/params:\s*\{\s*id\s*:\s*\{\s*slug\s*:\s*string\s*\}\s*\}/params: { sku: { slug: string } }/g' \
    -e 's/\/\[id\]/\/[sku]/g'
}
patch_glob app/admin/products
patch_glob app/api/products
patch_glob app/api/products/attributes

# 4) Sjekk igjen for kollisjon (feil bruk av annen slug)
CONFLICTS="$(find app -type d -path '*/products/[[]*[]]' -print | sed -n '/\[sku\]/!p' || true)"
if [ -n "$CONFLICTS" ]; then
  log "ADVARSEL: Fant fortsatt andre slug-mapper enn [sku]:"
  echo "$CONFLICTS"
fi

# 5) Rydd cache og restart dev i bakgrunn (best effort)
log "Tømmer .next og frigjør :3000"
rm -rf .next
lsof -ti :3000 2>/dev/null | xargs -r kill -9 2>/dev/null || true

log "Starter dev (silent) …"
npm run dev --silent >/tmp/next-dev.log 2>&1 &
pid=$!

# 6) Enkel readiness (inntil 25s). Faller tilbake til loggvisning ved feil.
BASE="${BASE:-http://localhost:3000}"
deadline=$((SECONDS+25)); ok=0
while [ $SECONDS -lt $deadline ]; do
  if curl -fsS "$BASE/api/debug/health" >/dev/null 2>&1; then ok=1; break; fi
  # prøv en kjent rute også i tilfelle health ikke er installert
  if curl -fsS "$BASE/api/products/merged?page=1&size=1" >/dev/null 2>&1; then ok=1; break; fi
  sleep 1
done

if [ $ok -ne 1 ]; then
  log "Dev ikke verifisert. Viser de første linjene fra /tmp/next-dev.log:"
  sed -n '1,120p' /tmp/next-dev.log || true
  exit 0
fi

# 7) Rask røyk-test
log "Røyk-test: attributes/TEST (dynamisk)"
curl -sS -D- "$BASE/api/products/attributes/TEST" -o /tmp/attr.json | head -n1 || true
file -b --mime-type /tmp/attr.json 2>/dev/null || true
head -c 200 /tmp/attr.json 2>/dev/null || true
echo

log "Røyk-test: completeness?sku=TEST"
curl -s "$BASE/api/products/completeness?sku=TEST" | jq -r '.items[0] | {sku,family,score:.completeness.score} // .'

#!/usr/bin/env bash
set -euo pipefail

# === Installer: skriver (og overskriver) category-sync.sh ===
cat > category-sync.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
: "${BASE:?}"; : "${AUTH_ADMIN:?}"
READ_BASE="${READ_BASE:-$BASE/rest/all/V1}"
WRITE_BASE="${WRITE_BASE:-$BASE/rest/V1}"

usage(){
  cat <<USAGE
Bruk:
  ./category-sync.sh --file <categories.csv> --mode attach|replace [--dry-run]

CSV-format:
  sku,category_ids
  TEST-RED,"2,4"
  TEST-GREEN,"2,5,7"
  TEST-BLUE-EXTRA,2;7   # inline-kommentarer og ';' støttes

Merknader:
- attach: bevarer eksisterende kategorier og legger til manglende.
- replace: erstatter med eksakt sett.
USAGE
  exit 1
}

CSV_FILE=""
MODE=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) CSV_FILE="${2:-}"; shift 2;;
    --mode) MODE="${2:-}"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    -h|--help) usage;;
    *) echo "Ukjent flagg: $1"; usage;;
  endac
done

[[ -f "$CSV_FILE" ]] || { echo "Finner ikke CSV: $CSV_FILE"; usage; }
[[ "$MODE" == "attach" || "$MODE" == "replace" ]] || { echo "Ugyldig --mode: $MODE"; usage; }

# Hjelper: lag JSON-array med tall fra "2,5,7" eller "2;5;7"
to_json_array_numbers() {
  # Input: en linje med ids (kan inneholde ; eller , og whitespace/kommentar)
  local s="$1"
  # fjern inline-kommentar
  s="${s%%#*}"
  # bytt ; -> ,
  s="${s//;/,}"
  # fjern whitespace
  s="$(printf '%s' "$s" | tr -d '[:space:]')"
  # til array av tall
  printf '%s' "$s" | tr ',' '\n' | sed '/^$/d' | jq -Rnc '[inputs | select(test("^[0-9]+$")) | tonumber]'
}

# Finn eksisterende category_ids for et SKU (som JSON array av tall)
get_have_categories() {
  local sku="$1"
  curl -sS -H "$AUTH_ADMIN" \
    "$READ_BASE/products/$sku?fields=sku,custom_attributes" \
  | jq -c '
      (.custom_attributes // [])
      | map(select(.attribute_code=="category_ids") | .value)[0] // []
      | map(tonumber?)
      | map(select(.!=null))
    '
}

# PUT category_ids for et SKU
put_categories() {
  local sku="$1" json_array="$2"
  local body
  body="$(jq -n --arg sku "$sku" --argjson arr "$json_array" \
    '{product:{sku:$sku, custom_attributes:[{attribute_code:"category_ids", value:$arr}]}}')"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY-RUN: would PUT $sku => $json_array"
  else
    curl -sS --fail -X PUT -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
      --data "$body" "$WRITE_BASE/products/$sku" >/dev/null
  fi
}

# Les CSV (robust):
# - hopper over tomme linjer
# - hopper over linjer som starter med #
# - første linje antas header
# - støtter at category_ids-feltet er i "" eller ikke
{
  IFS= read -r header || true
  while IFS= read -r line || [[ -n "$line" ]]; do
    # trim
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "${line#\#}" != "$line" ]] && continue

    # Vi tar første felt som sku, resten som raw categories
    # Støtt at category-felt kan ha komma i sitater; bruk awk til å hente 1. felt
    sku="$(printf '%s\n' "$line" | awk -F',' '{
      # Hent første CSV-felt korrekt (tar hensyn til sitater)
      s=$0
      q=0; out=""; for(i=1;i<=length(s);i++){
        c=substr(s,i,1)
        if(c=="\"" && (i==1 || substr(s,i-1,1)!="\\") ){ q=1-q; out=out c; }
        else if(c=="," && q==0){ break; }
        else{ out=out c; }
      }
      # fjern ev. sitater
      gsub(/^\"|\"$/,"",out); print out
    }')"

    rest="${line#"$sku"}"
    rest="${rest#,}"

    # Fjern ytre sitater rundt rest hvis de finnes
    if [[ "${rest:0:1}" == '"' && "${rest: -1}" == '"' ]]; then
      rest="${rest:1:${#rest}-2}"
    fi

    # Normaliser rest → JSON array av tall
    want="$(to_json_array_numbers "$rest")"
    [[ -z "$sku" ]] && continue

    have="$(get_have_categories "$sku" 2>/dev/null || echo '[]')"
    [[ -z "$have" || "$have" == "null" ]] && have='[]'

    if [[ "$MODE" == "attach" ]]; then
      merged="$(jq -c --argjson a "$have" --argjson b "$want" '($a + $b) | unique')"
      echo "[$sku] attach: $have  ->  $merged"
      put_categories "$sku" "$merged" && echo "✅ $sku oppdatert"
    else
      # replace
      echo "[$sku] replace: $have  ->  $want"
      put_categories "$sku" "$want" && echo "✅ $sku oppdatert"
    fi
  done
} < "$CSV_FILE"
SCRIPT

chmod +x category-sync.sh
echo "✅ category-sync.sh oppdatert."

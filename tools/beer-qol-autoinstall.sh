#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="$ROOT/tools"
HOOKS="$ROOT/.git/hooks"

need() { command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1 — please install it"; exit 1; }; }
need curl
need jq

echo "📦 Project root: $ROOT"
mkdir -p "$TOOLS"
mkdir -p "$HOOKS"

# -------------------------------
# 1) Install/refresh QoL helper file
# -------------------------------
cat > "$TOOLS/beer-qol.sh" <<"SH"
#!/usr/bin/env bash
# Helper functions for beer attrs (app + Magento)

: "${BASE_APP:=http://localhost:3000}"
: "${MAGENTO_URL:?set MAGENTO_URL in .env.local}"
V1="${MAGENTO_URL%/}/V1"

admin_jwt() {
  # needs MAGENTO_ADMIN_USERNAME / MAGENTO_ADMIN_PASSWORD in env
  if [[ -z "${MAGENTO_ADMIN_USERNAME:-}" || -z "${MAGENTO_ADMIN_PASSWORD:-}" ]]; then
    echo "❌ MAGENTO_ADMIN_USERNAME/PASSWORD mangler i miljøet" >&2
    return 1
  fi
  curl -sS -X POST "$V1/integration/admin/token" \
    -H 'Content-Type: application/json' \
    --data '{"username":"'"$MAGENTO_ADMIN_USERNAME"'","password":"'"$MAGENTO_ADMIN_PASSWORD"'"}' \
  | tr -d '"'
}

app_json() {  # app_json <url>  -> 0 if valid JSON
  curl -s -H 'Accept: application/json' "$1" | jq -e . >/dev/null 2>&1
}

appget() {
  local sku="${1:?bruk: appget <SKU>}"
  local u1="$BASE_APP/api/products/$sku"
  local u2="$BASE_APP/api/products/merged?page=1&size=200"

  app_json "$u1" || { echo "⚠️  $u1 returnerte ikke JSON (dev-server bygger?)"; return 1; }
  curl -s -H 'Accept: application/json' "$u1" \
    | jq '{sku,ibu,srm,hop_index,malt_index,_attrs:{ibu:._attrs.ibu,ibu2:._attrs.ibu2,srm:._attrs.srm,hop_index:._attrs.hop_index,malt_index:._attrs.malt_index}}'

  app_json "$u2" || { echo "⚠️  $u2 returnerte ikke JSON (dev-server bygger?)"; return 1; }
  curl -s -H 'Accept: application/json' "$u2" \
    | jq --arg sku "$sku" '.items[]?|select(.sku==$sku)|{sku,ibu,srm,hop_index,malt_index,_attrs:{ibu:._attrs.ibu,ibu2:._attrs.ibu2,srm:._attrs.srm,hop_index:._attrs.hop_index,malt_index:._attrs.malt_index}}'
}

mageget() {
  local sku="${1:?bruk: mageget <SKU>}"
  local jwt; jwt="$(admin_jwt)" || return 1
  curl -g -sS -H "Authorization: Bearer $jwt" \
    "$V1/products/$sku?storeId=0&fields=sku,custom_attributes%5Battribute_code%2Cvalue%5D" \
  | jq '.custom_attributes[]?|select(.attribute_code|IN("ibu","ibu2","srm","hop_index","malt_index"))'
}

appset() {
  local sku="${1:?bruk: appset <SKU> [ibu] [ibu2] [srm] [hop_index] [malt_index]}"
  local _ibu="${2:-}" _ibu2="${3:-}" _srm="${4:-}" _hop="${5:-}" _malt="${6:-}"
  local payload='{"sku":"'"$sku"'","attributes":{}}'
  [[ -n "$_ibu"  ]] && payload="$(jq --arg v "$_ibu"  '.attributes.ibu=$v'        <<<"$payload")"
  [[ -n "$_ibu2" ]] && payload="$(jq --arg v "$_ibu2" '.attributes.ibu2=$v'       <<<"$payload")"
  [[ -n "$_srm"  ]] && payload="$(jq --arg v "$_srm"  '.attributes.srm=$v'        <<<"$payload")"
  [[ -n "$_hop"  ]] && payload="$(jq --arg v "$_hop"  '.attributes.hop_index=$v'  <<<"$payload")"
  [[ -n "$_malt" ]] && payload="$(jq --arg v "$_malt" '.attributes.malt_index=$v' <<<"$payload")"
  curl -s -X PATCH "$BASE_APP/api/products/update-attributes" \
    -H 'Content-Type: application/json' -d "$payload" | jq '.success // .'
}

beer-smoke() {
  local sku="${1:?bruk: beer-smoke <SKU>}"
  echo "✍️  write via app (noop if same values)…"
  appset "$sku" 42 42 12 75 55 >/dev/null || true
  echo "🔎 app (single)"
  appget "$sku" | sed -n '1,12p' || true
  echo "🔎 magento (jwt)"
  mageget "$sku" || true
}
SH
chmod +x "$TOOLS/beer-qol.sh"

# -------------------------------
# 2) Ensure per-user helper loader
# -------------------------------
HELPER="$HOME/.m2-helpers.sh"
cat > "$HELPER" <<SH
# Auto-loaded beer helpers
export BASE_APP="\${BASE_APP:-http://localhost:3000}"
# VSCode bash guard (safe even if repeated)
: "\${VSCODE_PYTHON_AUTOACTIVATE_GUARD:=}"
# Load project helpers when present
[ -f "$TOOLS/beer-qol.sh" ] && source "$TOOLS/beer-qol.sh"
SH

# zsh profile
grep -qF 'source "$HOME/.m2-helpers.sh"' "$HOME/.zshrc" 2>/dev/null || \
  echo 'source "$HOME/.m2-helpers.sh"' >> "$HOME/.zshrc"

# bash profile(s)
for f in "$HOME/.bashrc" "$HOME/.bash_profile"; do
  touch "$f"
  grep -qF 'source "$HOME/.m2-helpers.sh"' "$f" 2>/dev/null || \
    echo 'source "$HOME/.m2-helpers.sh"' >> "$f"
  grep -qF 'VSCODE_PYTHON_AUTOACTIVATE_GUARD' "$f" 2>/dev/null || \
    echo ': "${VSCODE_PYTHON_AUTOACTIVATE_GUARD:=}"' >> "$f"
done

# -------------------------------
# 3) Pre-commit mini smoke (optional but handy)
# -------------------------------
cat > "$HOOKS/pre-commit" <<"SH"
#!/usr/bin/env bash
set -euo pipefail
BASE_APP="${BASE_APP:-http://localhost:3000}"
SKU="${SKU:-TEST-RED}"
U="$BASE_APP/api/products/$SKU"
if ! curl -s -H 'Accept: application/json' "$U" | jq -e '.sku' >/dev/null 2>&1; then
  echo "❌ API svarte ikke JSON på $U (dev-server nede eller bygger?). Avbryter commit."
  exit 1
fi
echo "✅ API OK – commit tillatt"
SH
chmod +x "$HOOKS/pre-commit"

echo "✅ QoL helpers installert."
echo "   • Kilde: $TOOLS/beer-qol.sh"
echo "   • Shell-loader: $HELPER"
echo "   • Git hook: $HOOKS/pre-commit"
echo
echo "🔁 Åpne nytt terminalvindu, eller kjør:  source ~/.zshrc   (evt: source ~/.bashrc)"
echo "🧪 Test:  appget TEST-RED   |  mageget TEST-RED   |  appset TEST-RED 43 43 13 76 56   |  beer-smoke TEST-RED"
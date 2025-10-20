#!/usr/bin/env bash
set -euo pipefail
BASE="http://localhost:3000"; SIZE=200; PAGE=1; patched=0
while :;do
 json="$(curl -s "$BASE/api/products/merged?page=$PAGE&size=$SIZE")"
 count="$(jq -r '.items|length'<<<"$json")";[[ "$count" -gt 0 ]]||break
 echo "🔎 Side $PAGE ($count produkter)…"
 echo "$json"|jq -c '.items[]|{sku,ibu,ibu2:(._attrs.ibu2//null)}'|while read -r row;do
  sku="$(jq -r '.sku'<<<"$row")";ibu="$(jq -r '.ibu'<<<"$row")";ibu2="$(jq -r '.ibu2'<<<"$row")"
  if [[ "$ibu"=="null" && "$ibu2"!="null" ]];then
    echo "✍️  $sku: setter ibu=$ibu2 (fra ibu2)"
    curl -s -X PATCH "$BASE/api/products/update-attributes" -H 'Content-Type: application/json' \
      --data "{\"sku\":\"$sku\",\"attributes\":{\"ibu\":\"$ibu2\"}}" >/dev/null
    patched=$((patched+1))
  fi
 done
 PAGE=$((PAGE+1))
done
echo "✅ Ferdig. Oppdaterte $patched produkter."

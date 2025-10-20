# tools/ibu-backfill-all.sh
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

BASE="${BASE:-http://localhost:3000}"
SIZE="${SIZE:-200}"
DRY="${DRY_RUN:-0}"   # set DRY_RUN=1 to simulate

page=1
total_seen=0
total_missing=0
total_patched=0

echo "🔎 Backfill scan (base=$BASE size=$SIZE dry_run=$DRY)…"

while :; do
  json="$(curl -s "$BASE/api/products/merged?page=$page&size=$SIZE")" || { echo "❌ fetch failed on page $page"; exit 1; }

  # Bail if route returned an error object
  if jq -e 'has("error")' >/dev/null <<<"$json"; then
    echo "❌ route error on page $page:"; echo "$json" | jq .
    exit 1
  fi

  count_this_page="$(jq -r '.items|length // 0' <<<"$json")"
  (( count_this_page == 0 )) && break
  (( total_seen += count_this_page ))

  # rows: sku, ibu, ibu2 (from _attrs)
  jq -c '.items[] | {sku, ibu, ibu2: (._attrs.ibu2 // null)}' <<<"$json" | while read -r row; do
    sku="$(jq -r '.sku' <<<"$row")"
    ibu="$(jq -r '.ibu' <<<"$row")"
    ibu2="$(jq -r '.ibu2' <<<"$row")"

    if [[ "$ibu" == "null" && "$ibu2" != "null" ]]; then
      (( total_missing += 1 ))
      if [[ "$DRY" == "1" ]]; then
        echo "🟡 DRY $sku: would set ibu=$ibu2 (from ibu2)"
      else
        echo "✍️  $sku: set ibu=$ibu2 (from ibu2)"
        curl -s -X PATCH "$BASE/api/products/update-attributes" \
          -H 'Content-Type: application/json' \
          -d "{\"sku\":\"$sku\",\"attributes\":{\"ibu\":\"$ibu2\"}}" >/dev/null || {
            echo "   ⚠️  PATCH failed for $sku"
          }
        (( total_patched += 1 ))
      fi
    fi
  done

  (( count_this_page < SIZE )) && break
  (( page += 1 ))
done

echo "✅ Backfill complete. scanned=$total_seen missing_ibu=$total_missing patched=$total_patched dry_run=$DRY"
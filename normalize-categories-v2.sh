#!/usr/bin/env bash
set -euo pipefail
in="${1:-categories.csv}"
out="${2:-/dev/stdout}"

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
# Fjern CR + BOM + ZWSP
perl -pe 's/\r$//; s/\xEF\xBB\xBF//g; s/\xE2\x80\x8B//g' "$in" > "$tmp"

awk '
  BEGIN {
    OFS=","; print "sku,category_ids"
  }
  {
    line=$0
    gsub(/\r/,"",line)
    sub(/#.*/,"",line)                             # kutt inline-kommentarer
    if (line ~ /^[[:space:]]*$/) next              # hopp blanke
    # hopp original header hvis tilstede
    if (NR==1 && line ~ /^[[:space:]]*sku[[:space:]]*,/) next

    # sku = alt før første komma
    sku=line; sub(/,.*/,"",sku)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", sku)
    if (sku=="") next

    # rest = alt etter første komma
    rest=line; sub(/^[^,]*,/, "", rest)

    # normalize: semikolon -> komma, kutt evt. kommentar
    gsub(/;/,",", rest)
    sub(/#.*/,"",rest)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", rest)

    # hvis hele feltet er sitert én gang ("…"/'…'), fjern ytre sitat
    if (rest ~ /^".*"$/) { rest=substr(rest,2,length(rest)-2) }
    else if (rest ~ /^'\''.*'\''$/) { rest=substr(rest,2,length(rest)-2) }

    # splitt og behold kun tall
    n=split(rest, raw, /,/)
    out_ids=""
    for (i=1;i<=n;i++) {
      x=raw[i]
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", x)
      if (x ~ /^[0-9]+$/) {
        out_ids = (out_ids=="" ? x : out_ids "," x)
      }
    }
    print sku, "\"" out_ids "\""
  }
' "$tmp" > "$out"

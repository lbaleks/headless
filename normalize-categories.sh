#!/usr/bin/env bash
set -euo pipefail
in="${1:-categories.csv}"
out="${2:-/dev/stdout}"

# Fjern CRLF og skjulte BOM/ZWSP → til temp
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
perl -pe 's/\r$//; s/\xEF\xBB\xBF//g; s/\xE2\x80\x8B//g' "$in" > "$tmp"

# Skriv kanonisk CSV: header + hver rad på formen: sku,"2,5,7"
awk -F',' '
  BEGIN {
    print "sku,category_ids"
  }
  {
    line=$0
    gsub(/\r/,"",line)
    sub(/#.*/,"",line)                       # kutt inline-kommentarer
    if (line ~ /^[[:space:]]*$/) next        # hopp blanke
    if (NR==1 && line ~ /^[[:space:]]*sku[[:space:]]*,/) next  # hopp original header

    # sku = alt før første komma
    sku=line; sub(/,.*/,"",sku)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", sku)
    if (sku=="") next

    # rest = alt etter første komma
    rest=line; sub(/^[^,]*,/, "", rest)
    gsub(/;/,",", rest)                      # semikolon → komma
    sub(/#.*/,"",rest)                       # evt. kommentar etter lista

    # splitt og behold bare tall
    n=split(rest, raw, /,/)
    out_ids=""
    for (i=1;i<=n;i++) {
      x=raw[i]
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", x)
      if (x ~ /^[0-9]+$/) {
        if (out_ids!="") out_ids=out_ids "," x
        else out_ids=x
      }
    }
    print sku ",\"" out_ids "\""
  }
' "$tmp" > "$out"

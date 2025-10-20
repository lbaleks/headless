#!/usr/bin/env bash
set -euo pipefail
in="${1:-categories.csv}"
out="${2:-/dev/stdout}"

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT

# Fjern CR, BOM, ZWSP
perl -pe 's/\r$//; s/\xEF\xBB\xBF//g; s/\xE2\x80\x8B//g' "$in" > "$tmp"

awk '
  BEGIN { OFS=","; print "sku,category_ids" }
  {
    line=$0
    gsub(/\r/,"",line)
    sub(/#.*/,"",line)                          # kutt inline-kommentarer
    if (line ~ /^[[:space:]]*$/) next           # hopp blanke
    if (NR==1 && line ~ /^[[:space:]]*sku[[:space:]]*,/) next  # hopp original header

    # sku = alt før første komma
    sku=line; sub(/,.*/,"",sku)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", sku)
    if (sku=="") next

    # rest = alt etter første komma
    rest=line; sub(/^[^,]*,/, "", rest)

    # fjern ytre sitat hvis hele feltet er sitert
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", rest)
    if (rest ~ /^".*"$/) { rest=substr(rest,2,length(rest)-2) }
    else if (rest ~ /^'\''.*'\''$/) { rest=substr(rest,2,length(rest)-2) }

    # normaliser: semikolon->komma for parsing
    gsub(/;/,",",rest)

    # splitt og behold kun rene heltall
    n=split(rest, raw, /,/)
    ids=""
    for (i=1;i<=n;i++) {
      x=raw[i]
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", x)
      if (x ~ /^[0-9]+$/) {
        ids = (ids=="" ? x : ids ";" x)         # <- skriv UT med semikolon
      }
    }

    print sku, ids
  }
' "$tmp" > "$out"

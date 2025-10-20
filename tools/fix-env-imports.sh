#!/bin/bash
set -euo pipefail

fix() { # file target
  local f="$1"; local t="$2"
  [ -f "$f" ] || { echo "skip: $f"; return; }
  # replace both alias and any previous wrong relative
  perl -0777 -pe 's#from\s+[\'"]@/lib/env[\'"]#from "'"$t"'"#g;
                  s#from\s+[\'"][.]{1,5}/(?:[.]{1,5}/)*lib/env[\'"]#from "'"$t"'"#g' -i "$f"
  echo "✓ $f  →  $t"
}

# Depths from each route to project root:
# app/api/products/update-attributes/route.ts  → root: ../../../../
# app/api/products/route.ts                    → root: ../../../
# app/api/products/merged/route.ts             → root: ../../../../

fix app/api/products/update-attributes/route.ts ../../../../lib/env
fix app/api/products/route.ts ../../../lib/env
fix app/api/products/merged/route.ts ../../../../lib/env

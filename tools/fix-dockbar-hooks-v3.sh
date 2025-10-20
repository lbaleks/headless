#!/bin/bash
set -euo pipefail
FILE="src/components/DockBar.tsx"
[ -f "$FILE" ] || { echo "Fant ikke $FILE"; exit 0; }

# 1) Drop any stray 'use client' lines
perl -0777 -i -pe 's/^\s*["\']use client["\'];\s*\n//mg' "$FILE"

# 2) Ensure "use client" is the first line
ed -s "$FILE" <<'ED'
g/^\s*['"]use client['"];\s*$/d
1i
"use client";
.
wq
ED

# 3) Normalize React import to include useState
#    Replace common variants with a single canonical import
perl -0777 -i -pe '
  s/^import\s+\*\s+as\s+React\s+from\s+["\']react["\'];?/import React, { useState } from "react";/m;
  s/^import\s+React\s+from\s+["\']react["\'];?/import React, { useState } from "react";/m;
  s/^import\s*\{\s*useState\s*\}\s*from\s*["\']react["\'];?\s*\n?//m;
' "$FILE"

# 4) If still no react import, insert it after the first line
if ! grep -qE '^import .* from ["'\'']react["'\'']' "$FILE"; then
  awk 'NR==1{print; print "import React, { useState } from \"react\";"; next}1' "$FILE" > "$FILE.tmp" \
    && mv "$FILE.tmp" "$FILE"
fi

echo "✅ Patchet $FILE"

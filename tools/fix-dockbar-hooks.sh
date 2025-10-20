#!/bin/bash
set -euo pipefail
FILE="src/components/DockBar.tsx"
[ -f "$FILE" ] || { echo "Fant ikke $FILE"; exit 0; }

# a) Remove any existing 'use client' lines (wherever they are)
perl -0777 -i -pe 's/^\s*["\']use client["\'];\s*\n//mg' "$FILE"

# b) Ensure "use client" is the first line
tmp="$(mktemp)"
printf '"use client";\n' > "$tmp"
cat "$FILE" >> "$tmp"
mv "$tmp" "$FILE"

# c) Normalize React import to include useState
#    Replace any variant of importing react with: import React, { useState } from "react";
perl -0777 -i -pe 's/^import\s+\*\s+as\s+React\s+from\s+["\']react["\'];?/import React, { useState } from "react";/m' "$FILE"
perl -0777 -i -pe 's/^import\s+React\s+from\s+["\']react["\'];?/import React, { useState } from "react";/m' "$FILE"
perl -0777 -i -pe 's/^import\s*\{\s*useState\s*\}\s*from\s*["\']react["\'];?//m' "$FILE"

# d) If there is still no react import, insert it after the first line
if ! grep -qE '^import .* from ["\']react["\'];?' "$FILE"; then
  awk 'NR==1{print; print "import React, { useState } from \"react\";"; next}1' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"
fi

echo "✅ Patchet $FILE"

#!/bin/sh
set -eu

mkdir -p src/components

TARGET="src/components/BulkEditDialog.tsx"
if [ ! -f "$TARGET" ]; then
  cat > "$TARGET" <<'TSX'
"use client";
import React, { useState } from "react";

type Props = {
  onApply?: (action: "delete" | "publish" | "unpublish") => void;
}

/**
 * Minimal BulkEditDialog:
 * - Viser en "Bulk actions"-knapp
 * - En enkel dialog med 3 dummy-aksjoner
 * - Kaller optional onApply, ellers bare lukker
 */
export function BulkEditDialog({ onApply }: Props) {
  const [open, setOpen] = useState(false);

  const apply = (action: "delete" | "publish" | "unpublish") => {
    try {
      onApply?.(action);
    } finally {
      setOpen(false);
    }
  };

  return (
    <div className="p-2">
      <button
        type="button"
        className="px-3 py-2 rounded border hover:bg-black/5"
        onClick={() => setOpen(true)}
      >
        Bulk actions
      </button>

      {open && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div className="absolute inset-0 bg-black/40" onClick={() => setOpen(false)} />
          <div className="relative z-10 bg-white dark:bg-neutral-900 rounded-xl shadow-xl w-[90vw] max-w-md p-4">
            <h2 className="text-lg font-semibold mb-3">Bulk actions</h2>
            <div className="space-y-2">
              <button
                type="button"
                className="w-full text-left px-3 py-2 rounded border hover:bg-black/5"
                onClick={() => apply("publish")}
              >
                Publish selected
              </button>
              <button
                type="button"
                className="w-full text-left px-3 py-2 rounded border hover:bg-black/5"
                onClick={() => apply("unpublish")}
              >
                Unpublish selected
              </button>
              <button
                type="button"
                className="w-full text-left px-3 py-2 rounded border hover:bg-red-50 dark:hover:bg-red-900/20"
                onClick={() => apply("delete")}
              >
                Delete selected
              </button>
            </div>
            <div className="mt-4 text-right">
              <button
                type="button"
                className="px-3 py-2 rounded border hover:bg-black/5"
                onClick={() => setOpen(false)}
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default BulkEditDialog;
TSX
  echo "✓ Opprettet $TARGET"
else
  echo "• $TARGET finnes allerede"
fi

# 2) Rette alias og sikre import i products-siden
FILE="app/admin/products/page.tsx"
if [ -f "$FILE" ]; then
  # a) Bytt evt. feil alias
  perl -0777 -i -pe "s#['\"]@/src/components/BulkEditDialog['\"]#'@/components/BulkEditDialog'#g" "$FILE"

  # b) Sett inn import om mangler (plasser under ev. 'use client')
  perl -0777 -i -pe '
    my $needs = ($_ =~ /<\s*BulkEditDialog\b/ && $_ !~ /from\s+["\x27]@\/components\/BulkEditDialog["\x27]/);
    if ($needs) {
      if ($_ =~ /^["\x27]use client["\x27];?\s*\R/) {
        s/^(["\x27]use client["\x27];?\s*\R)/$1import BulkEditDialog, { BulkEditDialog as _BulkEditDialogNamed } from "\@\/components\/BulkEditDialog";\n/s;
      } else {
        s/\A/import BulkEditDialog, { BulkEditDialog as _BulkEditDialogNamed } from "\@\/components\/BulkEditDialog";\n/s;
      }
    }
    $_;
  ' "$FILE"
fi

echo "✅ BulkEditDialog klar og import fikset."

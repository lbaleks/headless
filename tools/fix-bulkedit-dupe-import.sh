#!/bin/sh
set -eu

FILE="src/components/BulkEditDialog.tsx"
mkdir -p "$(dirname "$FILE")"

# Skriv en ren versjon som ikke dobbel-importerer useState
cat > "$FILE" <<'TSX'
"use client";

import { useState } from "react";

type Props = {
  onApply?: (action: "delete" | "publish" | "unpublish") => void;
};

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

echo "✓ BulkEditDialog.tsx skrevet på nytt uten duplisert import"

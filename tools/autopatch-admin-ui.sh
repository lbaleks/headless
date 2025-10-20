#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADMIN="$ROOT/app/admin"

echo "→ Patcher admin-UI (idempotent)…"

# ---------- helpers ----------
add_import_once() {
  local file="$1" line="$2"
  [ -f "$file" ] || { echo "  • SKIP (mangler): ${file#$ROOT/}"; return 0; }
  grep -qF "$line" "$file" && { echo "  • import finnes alt: ${file#$ROOT/}"; return 0; }

  awk -v ins="$line" '
    BEGIN{insdone=0; last=0}
    /^[[:space:]]*import[[:space:]]/ { last=NR }
    { buf[NR]=$0 }
    END{
      for(i=1;i<=length(buf);i++){
        print buf[i]
        if(i==last && !insdone){ print ins; insdone=1 }
      }
      if(last==0 && !insdone){ print ins }
    }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  echo "  • la til import i ${file#$ROOT/}"
}

insert_bulk_dialog_before_table() {
  local file="$1"
  [ -f "$file" ] || return 0
  grep -q "<BulkEditDialog" "$file" && { echo "  • BulkEditDialog finnes alt: ${file#$ROOT/}"; return 0; }

  # If a <table exists: insert the component right before the first <table
  if grep -q "<table" "$file"; then
    awk '
      BEGIN{done=0}
      /<table/ && !done { print "<BulkEditDialog />"; print ""; done=1 }
      { print }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    echo "  • BulkEditDialog lagt inn før første <table> i ${file#$ROOT/}"
  else
    # No table found — append near end as a fallback
    printf "\n<BulkEditDialog />\n" >> "$file"
    echo "  • BulkEditDialog lagt inn (fallback) i ${file#$ROOT/}"
  fi
}

replace_customers_tr_key() {
  local file="$1"
  [ -f "$file" ] || return 0
  # Make <tr key={...}> stable: prefer id → email → index
  perl -0777 -pe 's#<tr\s+key=\{[^}]*\}#<tr key={(c.id ?? c.email ?? String(i))}#g' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  echo "  • Stabil <tr key> i ${file#$ROOT/}"
}

ensure_jobs_footer() {
  local file="$1"
  [ -f "$file" ] || return 0
  add_import_once "$file" "import { JobsFooter } from '@/src/components/JobsFooter'"
  # Inject before </main> (preferred), else </body>, else </html>
  if ! grep -q "<JobsFooter" "$file"; then
    perl -0777 -pe '
      BEGIN{ $ins=0 }
      if(!$ins && s#</main>#<JobsFooter />\n</main>#s){ $ins=1 }
      if(!$ins && s#</body>#<JobsFooter />\n</body>#s){ $ins=1 }
      if(!$ins && s#</html>#<JobsFooter />\n</html>#s){ $ins=1 }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    echo "  • JobsFooter lagt til i ${file#$ROOT/}"
  else
    echo "  • JobsFooter finnes alt: ${file#$ROOT/}"
  fi
}

wire_completeness_badge() {
  local file="$1"
  [ -f "$file" ] || return 0
  add_import_once "$file" "import { CompletenessBadge } from '@/src/components/CompletenessBadge'"
  perl -0777 -pe 's/\{p\.completeness\}/<CompletenessBadge score={Number(p?.completeness?.score ?? p?.completeness ?? 0)} \/>/g' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  perl -0777 -pe 's/\{item\.completeness\}/<CompletenessBadge score={Number(item?.completeness?.score ?? item?.completeness ?? 0)} \/>/g' "$file" > "$file.tmp2" && mv "$file.tmp2" "$file"
  echo "  • CompletenessBadge koblet (dersom feltet finnes) i ${file#$ROOT/}"
}

# ---------- locate pages ----------
find_one_page() {
  # $1: subdir (products|customers), $2: fallback file name
  local dir="$ADMIN/$1"
  local file=""
  if [ -f "$dir/page.tsx" ]; then file="$dir/page.tsx"
  else
    # first tsx under dir
    file="$(find "$dir" -maxdepth 2 -type f -name '*.tsx' 2>/dev/null | head -n1 || true)"
  fi
  printf '%s' "$file"
}

PROD_PAGE="$(find_one_page products page.tsx)"
CUST_PAGE="$(find_one_page customers page.tsx)"
LAYOUT="$ADMIN/layout.tsx"

# ---------- apply patches ----------
if [ -n "${PROD_PAGE:-}" ] && [ -f "$PROD_PAGE" ]; then
  add_import_once "$PROD_PAGE" "import { BulkEditDialog } from '@/src/components/BulkEditDialog'"
  insert_bulk_dialog_before_table "$PROD_PAGE"
  wire_completeness_badge "$PROD_PAGE"
else
  echo "  • Fant ikke products page (skipped)."
fi

if [ -n "${CUST_PAGE:-}" ] && [ -f "$CUST_PAGE" ]; then
  replace_customers_tr_key "$CUST_PAGE"
else
  echo "  • Fant ikke customers page (skipped)."
fi

if [ -f "$LAYOUT" ]; then
  ensure_jobs_footer "$LAYOUT"
else
  echo "  • Fant ikke admin layout (skipped)."
fi

echo "✓ Ferdig. Hvis hot-reload ikke plukker opp: npm run dev på nytt."

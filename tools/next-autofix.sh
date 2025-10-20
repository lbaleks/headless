#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
echo "🔧 Next Autofix – fikser Link/Image/a11y + kjører eslint --fix"
echo "→ Arbeidskatalog: $ROOT"

build_file_list() {
  find "$ROOT" \
    -type f \( -name "*.tsx" -o -name "*.ts" -o -name "*.jsx" -o -name "*.js" \) \
    -not -path "*/node_modules/*" -not -path "*/.next/*" -not -path "*/dist/*" -print0
}

ensure_import() {
  file="$1"; what="$2"; from="$3"
  if ! grep -qE "import[[:space:]]+${what}[[:space:]]+from[[:space:]]+[\"']${from}[\"'];?" "$file"; then
    if grep -qE "^import " "$file"; then
      awk -v imp="import ${what} from \"${from}\";" '
        BEGIN{added=0}
        { print $0 }
        END{ if(!added) print imp }
      ' "$file" > "$file.__tmp" && mv "$file.__tmp" "$file"
    else
      printf 'import %s from "%s";\n%s' "$what" "$from" "$(cat "$file")" > "$file"
    fi
  fi
}

echo "→ Konverterer <a> til <Link> for interne ruter"
build_file_list | while IFS= read -r -d '' f; do
  if grep -qE '<a[[:space:]][^>]*href="/[^"]*"' "$f"; then
    cp "$f" "$f.bak" 2>/dev/null || true
    perl -0777 -i -pe 's/<a\s+([^>]*?)\bhref="(\/[^"]*)"(.*?)>/<Link href="$2">/g' "$f"
    perl -0777 -i -pe 's/<\/a>/<\/Link>/g' "$f"
    ensure_import "$f" "Link" "next/link"
  fi
done

echo "→ Konverterer <img> til <Image /> (uten perl-eval)"
build_file_list | while IFS= read -r -d '' f; do
  if grep -qE '<img\s' "$f"; then
    cp "$f" "$f.bak" 2>/dev/null || true
    # Enkel og robust: <img ...> -> <Image ... />
    perl -0777 -i -pe 's/<img\s+([^>]*?)>/<Image \1 \/>/g; s|</img>||g' "$f"
    ensure_import "$f" "Image" "next/image"
  fi
done

echo "→ Legger til a11y-attributes på klikkbare div/span"
build_file_list | while IFS= read -r -d '' f; do
  if grep -qE '<(div|span)[^>]*onClick=' "$f"; then
    cp "$f" "$f.bak" 2>/dev/null || true
    perl -0777 -i -pe '
      s/<(div|span)((?:(?!>).)*)onClick=/<$1$2 role="button" tabIndex={0} onKeyDown={(e)=>{if(e.key==="Enter"||e.key===" "){(e.currentTarget as any).click();}}} onClick=/g;
      s/\srole="button"\s+role="button"//g;
    ' "$f"
  fi
done

echo "→ Rydder unødvendige escapes i strenger (\\. \\- \\/)"
build_file_list | while IFS= read -r -d '' f; do
  cp "$f" "$f.bak" 2>/dev/null || true
  perl -0777 -i -pe 's/([\'""])([^\'""]*?)\\\.(.*?\1)/$1$2\.$3/sg' "$f"
  perl -0777 -i -pe 's/([\'""])([^\'""]*?)\\\-(.*?\1)/$1$2\-$3/sg' "$f"
  perl -0777 -i -pe 's/([\'""])([^\'""]*?)\\\/(.*?\1)/$1$2\/$3/sg' "$f"
done

echo "→ Kjører eslint --fix"
if command -v pnpm >/dev/null 2>&1; then
  pnpm run lint --fix || true
elif command -v npm >/dev/null 2>&1; then
  npm run lint --fix || true
else
  npx eslint . --fix || true
fi

echo "✅ Ferdig! (.bak-filer ligger igjen for diff om ønskelig)"

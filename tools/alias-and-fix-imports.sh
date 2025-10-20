# tools/alias-and-fix-imports.sh
#!/bin/bash
set -euo pipefail

echo "🔧 Retter alias-importer, oppdaterer tsconfig-paths og flytter imports til toppen…"

# 1) Standardiser alias: "@/src/..." -> "@/..."
if compgen -G "app/**/*" >/dev/null || compgen -G "src/**/*" >/dev/null; then
  grep -rl '@/src/' app src 2>/dev/null | xargs -I{} sed -i '' -e 's#@/src/#@/#g' {}
fi

# 2) Legg til ekstra alias i tsconfig.json: "@src/*" -> "src/*"
if [ -f tsconfig.json ]; then
  node - <<'NODE'
const fs = require('fs');
const p = 'tsconfig.json';
const j = JSON.parse(fs.readFileSync(p, 'utf8'));
j.compilerOptions ||= {};
j.compilerOptions.baseUrl ||= '.';
j.compilerOptions.paths ||= {};
// Sørg for at begge alias peker til src/*
if (!j.compilerOptions.paths['@/*']) j.compilerOptions.paths['@/*'] = ['src/*'];
if (!j.compilerOptions.paths['@src/*']) j.compilerOptions.paths['@src/*'] = ['src/*'];
fs.writeFileSync(p, JSON.stringify(j, null, 2));
console.log('✅ tsconfig.json oppdatert (paths: @/* og @src/* -> src/*)');
NODE
fi

# 3) Fallback-komponent hvis AdminPage mangler
if [ ! -f src/components/AdminPage.tsx ]; then
  mkdir -p src/components
  cat > src/components/AdminPage.tsx <<'TSX'
import React from "react";
export function AdminPage({ title, children }: { title?: string; children?: React.ReactNode }) {
  return (
    <div className="p-6">
      {title ? <h1 className="text-xl font-semibold mb-4">{title}</h1> : null}
      <div>{children}</div>
    </div>
  );
}
export default AdminPage;
TSX
  echo "✅ La inn enkel fallback: src/components/AdminPage.tsx"
fi

# 4) Hoist 'import …' til toppen av .tsx-filer (fix for "import … cannot be used outside of module")
hoist_imports() {
  local f="$1"
  [ -f "$f" ] || return 0
  perl -0777 -i -pe '
    my $c = $_;

    # Finn alle import-linjer
    my @im = ($c =~ m/^[ \t]*import[^\n]*\n/gm);
    # Fjern dem fra innholdet
    $c =~ s/^[ \t]*import[^\n]*\n//gm;

    # Dedup importlinjer (bevar rekkefølge)
    my %seen; my @uniq;
    for my $l (@im) { push @uniq, $l unless $seen{$l}++; }
    my $imports = join("", @uniq);
    if ($imports eq "") { $_ = $c; next; }

    # Sett etter "use client" hvis den finnes i toppen, ellers helt øverst
    if ($c =~ s/\A([ \t]*[\'"]use client[\'"];[ \t]*\n)/$1$imports/s) {
      $_ = $c;
    } else {
      $_ = $imports . $c;
    }
  ' "$f"
}

# Kjør hoisting på kjente problemfiler først
[ -f app/admin/products/page.tsx ] && hoist_imports app/admin/products/page.tsx

# Og generell rydd for alle app-TSX (ufarlig; skipper filer uten imports)
while IFS= read -r -d '' file; do
  hoist_imports "$file"
done < <(find app -type f -name '*.tsx' -print0 2>/dev/null)

echo "✅ Imports hoistet og aliaser på plass."
echo "👉 Start på nytt: killall -9 node 2>/dev/null || true; pnpm dev"
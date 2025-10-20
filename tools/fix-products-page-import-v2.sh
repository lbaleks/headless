# tools/fix-products-page-import-v2.sh
#!/bin/bash
set -euo pipefail

F="app/admin/products/page.tsx"
[ -f "$F" ] || { echo "Finner ikke $F"; exit 1; }

echo "🔧 (v2) Rydder imports og cleanup i $F"

# 1) Flytt alle import-linjer til toppen (etter "use client" hvis finnes)
perl -0777 -pe '
  my $c = $_;

  # Samle alle imports
  my @im = ($c =~ m/^[ \t]*import[^\n]*\n/gm);

  # Fjern dem fra innholdet
  $c =~ s/^[ \t]*import[^\n]*\n//gm;

  # Dedupliser (behold rekkefølge)
  my (%seen, @uniq);
  for my $l (@im) { push @uniq, $l unless $seen{$l}++; }
  my $imports = join("", @uniq);

  # Hvis Link brukes i filen, sørg for at den importeres
  if ($c =~ /\blink\s*from\s*["\']next\/link["\']/i) {
    # allerede importert; ikke gjør noe
  } elsif ($c =~ /\b<Link\b/) {
    $imports = "import Link from '\''next/link'\'';\n" . $imports
      unless $imports =~ /from\s+["\']next\/link["\']/;
  }

  # Sett imports etter "use client" hvis den finnes på toppen, ellers helt øverst
  if ($c =~ s/\A(([ \t]*[\'"]use client[\'"];[^\n]*\n)+)/$1$imports/s) {
    $_ = $c;
  } else {
    $_ = $imports . $c;
  }
' < "$F" > "$F.tmp1"

# 2) Rydd opp feilplassert cleanup i useEffect
perl -0777 -pe '
  s/return\s*\(\)\s*=>\s*\{\s*mounted\s*=\s*false;?\s*clearTimeout\(watchdog\)\s*\}\s*;?/return () => { mounted = false; clearTimeout(watchdog); }/g;
  s/return\s*\(\)\s*=>\s*\{\s*mounted\s*=\s*false\s*;\s*\}\s*;?/return () => { mounted = false; clearTimeout(watchdog); }/g;
' < "$F.tmp1" > "$F.tmp2"

mv "$F.tmp2" "$F"
rm -f "$F.tmp1"

echo "✅ Ferdig. Starter dev på nytt…"
killall -9 node 2>/dev/null || true
pnpm dev
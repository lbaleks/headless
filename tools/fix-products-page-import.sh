# tools/fix-products-page-import.sh
#!/bin/bash
set -euo pipefail

F="app/admin/products/page.tsx"
[ -f "$F" ] || { echo "Finner ikke $F"; exit 1; }

echo "🔧 Rydder imports og cleanup i $F"

# 1) Samle ALLE import-linjer, dedupe, og flytt dem til toppen (etter 'use client' hvis den finnes)
perl -0777 -i -pe '
  my $c = $_;

  # Hent alle import-linjer i hele filen
  my @im = ($c =~ m/^[ \t]*import[^\n]*\n/gm);

  # Fjern ALLE import-linjer fra innholdet
  $c =~ s/^[ \t]*import[^\n]*\n//gm;

  # Dedupliser (i rekkefølge)
  my (%seen, @uniq);
  for my $l (@im) { push @uniq, $l unless $seen{$l}++; }
  my $imports = join("", @uniq);

  # Sørg for at Link-import finnes
  $imports = "import Link from '\''next/link'\'';\n" . $imports
    unless $imports =~ /from\s+['"]next\/link['"]/;

  # Sett imports etter "use client" hvis den finnes i første 5 linjer, ellers helt øverst
  if ($c =~ s/\A([ \t]*[\'"]use client[\'"];[^\n]*\n)/$1$imports/s) {
    $_ = $c;
  } else {
    $_ = $imports . $c;
  }
' "$F"

# 2) Rydd opp feilplassert cleanup:  return () => { mounted = false; clearTimeout(watchdog); };
perl -0777 -i -pe '
  s/return\s*\(\)\s*=>\s*\{\s*mounted\s*=\s*false;?\s*clearTimeout\(watchdog\)\s*\}\s*;?/return () => { mounted = false; clearTimeout(watchdog); }/g;
  s/return\s*\(\)\s*=>\s*\{\s*mounted\s*=\s*false\s*;\s*\}\s*;?/return () => { mounted = false; clearTimeout(watchdog); }/g;
' "$F"

# 3) Ekstra sikkerhet: hvis en "import Link ..." fortsatt finnes utenfor toppen, fjern den.
# (flytta importene skal allerede dekke dette, men vi trimmer ev. rester)
perl -0777 -i -pe '
  my $head = substr($_, 0, 1200);        # topp ~første 1200 tegn (import-blokka)
  my $body = substr($_, 1200);
  $body =~ s/^[ \t]*import\s+Link\s+from\s+[\'"]next\/link[\'"];\s*\n//gm;
  $_ = $head . $body;
' "$F"

echo "✅ Ferdig! Starter dev på nytt…"
killall -9 node 2>/dev/null || true
pnpm dev
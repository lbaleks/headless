#!/usr/bin/env bash
set -euo pipefail

FILE="app/api/orders/route.ts"
[ -f "$FILE" ] || { echo "Finner ikke $FILE"; exit 1; }

cp "$FILE" "$FILE.bak.$(date +%s)"

# Normaliser CRLF -> LF
perl -i -pe 's/\r\n/\n/g' "$FILE"

# Dedupe i én pass med Perl: fjern duplikate imports/consts og ekstra m2()/POST()-blokker
perl -0777 -ne '
  my $src = $_;

  # 1) Behold kun første NextResponse-import
  my $imp = qr/^import\s+\{\s*NextResponse\s*\}\s+from\s+.\x27next\/server\x27;\s*$/m;
  if ($src =~ /$imp/) {
    my $seen = 0;
    $src = join("\n", grep {
      if (/$imp/) { $seen++ ; $seen==1 }
      else { 1 }
    } split(/\n/, $src));
  }

  # 2) Behold kun første const M2_BASE / M2_TOKEN
  for my $k (qw(M2_BASE M2_TOKEN)) {
    my $re = qr/^\s*const\s+$k\s*=/m;
    my $seen = 0;
    $src = join("\n", grep {
      if (/$re/) { $seen++; $seen==1 }
      else { 1 }
    } split(/\n/, $src));
  }

  # 3) Fjern duplikate funksjonsblokker (m2 og POST) – behold første
  sub drop_dupe_block {
    my ($txt, $head_re) = @_;
    my $out = "";
    my $seen = 0;
    my $i = 0;
    my @lines = split(/\n/, $txt);
    while ($i <= $#lines) {
      my $line = $lines[$i];
      if ($line =~ $head_re) {
        $seen++;
        if ($seen > 1) {
          # dropp denne blocken med balanserte klammer
          my $brace = 0;
          # tell klammer på head-line
          my $opens = () = $line =~ /\{/g;
          my $closes = () = $line =~ /\}/g;
          $brace += $opens - $closes;
          $i++; # hopp over head-line
          while ($i <= $#lines) {
            my $l = $lines[$i];
            my $o = () = $l =~ /\{/g;
            my $c = () = $l =~ /\}/g;
            $brace += $o - $c;
            $i++;
            last if $brace <= 0;
          }
          next; # fortsett etter blokken
        }
      }
      $out .= $line."\n";
      $i++;
    }
    return $out;
  }

  # m2(...){...}
  my $m2_head = qr/^\s*async\s+function\s+m2\s*\(/;
  $src = drop_dupe_block($src, $m2_head);

  # export async function POST(...){...}
  my $post_head = qr/^\s*export\s+async\s+function\s+POST\s*\(/;
  $src = drop_dupe_block($src, $post_head);

  print $src;
' "$FILE" > "$FILE.tmp"

mv "$FILE.tmp" "$FILE"

# 4) Sikre at importen finnes, ellers legg inn øverst
if ! grep -q "import { NextResponse } from 'next/server';" "$FILE"; then
  printf "import { NextResponse } from 'next/server';\n%s" "$(cat "$FILE")" > "$FILE.tmp2"
  mv "$FILE.tmp2" "$FILE"
fi

echo "→ Rydder .next/.next-cache"
rm -rf .next .next-cache 2>/dev/null || true

echo "✓ Ferdig. Start dev på nytt: npm run dev"
echo "  Test POST (uten jq) for å verifisere JSON-status:"
echo "  curl -i -sS -X POST 'http://localhost:3000/api/orders' -H 'Content-Type: application/json' -H 'Accept: application/json' --data-binary '{\"customer\":{\"email\":\"dev+guest@example.com\"},\"lines\":[{\"sku\":\"TEST\",\"qty\":1}]}' | sed -n \"1,20p\""

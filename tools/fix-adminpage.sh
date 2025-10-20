#!/bin/sh
set -eu

# 1) Opprett komponent hvis den mangler
mkdir -p src/components
TARGET="src/components/AdminPage.tsx"
if [ ! -f "$TARGET" ]; then
  cat > "$TARGET" <<'TSX'
"use client";
import * as React from "react";

type AdminPageProps = {
  title?: string;
  actions?: React.ReactNode;
  children?: React.ReactNode;
};

export function AdminPage({ title, actions, children }: AdminPageProps) {
  return (
    <div className="min-h-[60vh]">
      {title ? (
        <div className="flex items-center justify-between px-4 py-3 border-b">
          <h1 className="text-xl font-semibold">{title}</h1>
          {actions ? <div className="flex items-center gap-2">{actions}</div> : null}
        </div>
      ) : null}
      <div className="p-4">{children}</div>
    </div>
  );
}

export default AdminPage;
TSX
  echo "✓ Opprettet $TARGET"
else
  echo "• $TARGET finnes allerede"
fi

# 2) Rette alias fra '@/src/components/AdminPage' -> '@/components/AdminPage'
#    og sikre import i sider som bruker AdminPage men mangler import
fix_import() {
  FILE="$1"
  [ -f "$FILE" ] || return 0

  # a) Bytt feil alias til korrekt alias
  perl -0777 -i -pe "s#['\"]@/src/components/AdminPage['\"]#'@/components/AdminPage'#g" "$FILE"

  # b) Hvis AdminPage brukes men ingen import finnes, sett inn import under ev. 'use client'
  perl -0777 -i -pe '
    my $needs = ( $_ =~ /\bAdminPage\b/ && $_ !~ /from\s+["\x27]@\/components\/AdminPage["\x27]/ );
    if ($needs) {
      if ($_ =~ /^["\x27]use client["\x27];?\s*\R/) {
        s/^(["\x27]use client["\x27];?\s*\R)/$1import { AdminPage } from "\@\/components\/AdminPage";\n/s;
      } else {
        s/\A/import { AdminPage } from "\@\/components\/AdminPage";\n/s;
      }
    }
    $_;
  ' "$FILE"
}

# Kjør på kjente filer (legg gjerne til flere ved behov)
fix_import "app/admin/products/page.tsx"
fix_import "app/admin/orders/page.tsx"
fix_import "app/admin/dashboard/page.tsx"
fix_import "admstage/app/admin/dashboard/page.tsx"
fix_import "admstage/app/admin/products/page.tsx"

echo "✅ AdminPage klar og imports rettet. Starter dev på nytt..."

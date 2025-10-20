#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
SHELL_FILE="$ROOT/src/components/AdminShell.tsx"

echo "→ Oppdaterer AdminShell.tsx (hydration-safe NavLink)…"
mkdir -p "$(dirname "$SHELL_FILE")"
cat > "$SHELL_FILE" <<'TS'
// NOTE: Hydration-safe AdminShell
'use client'

import React from 'react'
import Link from 'next/link'
import { usePathname } from 'next/navigation'

type NavLinkProps = {
  href: string
  children: React.ReactNode
}

function NavLink({ href, children }: NavLinkProps) {
  const pathname = usePathname() || '/'
  const active = pathname.startsWith(href)

  const base = 'block px-3 py-2 rounded text-sm transition-colors'
  const cls = active
    ? base + ' bg-neutral-900 text-white'
    : base + ' hover:bg-neutral-200 text-neutral-700'

  return (
    <Link href={href} className={cls}>
      {children}
    </Link>
  )
}

export function AdminShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen grid grid-cols-12">
      <aside className="hidden md:block col-span-3 lg:col-span-2 border-r bg-white">
        <div className="h-screen sticky top-0">
          <div className="p-3">
            <nav className="space-y-1">
              <NavLink href="/admin/dashboard">Dashboard</NavLink>
              <NavLink href="/admin/orders">Orders</NavLink>
              <NavLink href="/admin/products">Products</NavLink>
              <NavLink href="/admin/customers">Customers</NavLink>
              <NavLink href="/admin/settings">Settings</NavLink>
            </nav>
          </div>
        </div>
      </aside>
      <main className="col-span-12 md:col-span-9 lg:col-span-10">
        {children}
      </main>
    </div>
  )
}

export default AdminShell
TS

echo "→ Rydder .next-cache…"
rm -rf "$ROOT/.next" "$ROOT/.next/cache" 2>/dev/null || true
mkdir -p "$ROOT/.next"

echo "✓ Ferdig. Start dev-server på nytt:  npm run dev"

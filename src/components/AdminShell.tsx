"use client";
import React from 'react'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
// @ts-nocheck

function NavLink({ href, children }: { href: string; children: React.ReactNode }) {
  const pathname = usePathname() || '/'
  const isActive = pathname.startsWith(href)
  return (
    <Link
      href={href}
      className={
        'block px-3 py-2 rounded text-sm transition-colors ' +
        (isActive
          ? 'bg-neutral-900 text-white'
          : 'hover:bg-neutral-200 text-neutral-800')
      }
    >
      {children}
    </Link>
  )
}

export function AdminShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen grid grid-cols-12">
      <aside className="hidden md:block col-span-3 bg-white border-r">
        <div className="h-screen sticky top-0 p-3">
          <nav className="space-y-1">
            <NavLink href="/admin/dashboard">Dashboard</NavLink>
            <NavLink href="/admin/orders">Orders</NavLink>
            <NavLink href="/admin/products">Products</NavLink>
            <NavLink href="/admin/customers">Customers</NavLink>
          </nav>
        </div>
      </aside>
      <main className="col-span-12 md:col-span-9">{children}</main>
    </div>
  )
}

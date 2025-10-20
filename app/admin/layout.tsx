import SyncNow from "@/components/SyncNowMini";
import * as React from 'react'
import Link from "next/link";
import JobsFooter from "@/components/JobsFooter";
export default function AdminLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-neutral-50 text-neutral-900">
      <header className="border-b bg-white">
        <div className="mx-auto max-w-6xl px-4 py-3 flex items-center gap-6">
          <h1 className="font-semibold tracking-tight">Admin</h1>
          <nav className="text-sm flex gap-4">
            <Link href="/admin/products" className="hover:underline">Products</Link>
            <Link href="/admin/dashboard" className="hover:underline">Dashboard</Link>
            <Link href="/admin/orders" className="hover:underline">Orders</Link>
            <Link href="/admin/customers" className="hover:underline">Customers</Link>
          </nav>
          <div className="ml-auto text-xs text-neutral-500">
            API base: {process.env.NEXT_PUBLIC_BASE || "/"}
          </div>
        </div>
        <nav className="text-sm text-neutral-600">
        <Link href="/admin/completeness">Completeness</Link>
      </nav>
</header>
      <main className="mx-auto max-w-6xl px-4 py-6">{children}<JobsFooter /><SyncNow />
</main>
    </div>
  );
}

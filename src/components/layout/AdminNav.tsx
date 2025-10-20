'use client';
import Link from 'next/link'
import { usePathname } from 'next/navigation'
export default function AdminNav(){
  const p = usePathname()||'/'
  const Item=({href,label}:{href:string;label:string})=>{
    const active = p===href || p.startsWith(href+'/')
    return <Link href={href} className={`sidebar-link ${active?'sidebar-link--active':''}`}>{label}</Link>
  }
  return (
    <aside className="h-[100svh] sticky top-0 border-r bg-white/95 backdrop-blur supports-[backdrop-filter]:bg-white/80 w-[260px]">
      <div className="px-3 pt-3 pb-2 text-xs font-semibold text-neutral-500">NAVIGATION</div>
      <nav className="px-2 space-y-1">
        <Item href="/admin/dashboard" label="Dashboard"/>
        <Item href="/admin/orders" label="Orders"/>
        <Item href="/admin/products" label="Products"/>
        <Item href="/admin/customers" label="Customers"/>
        <Item href="/admin/pricing" label="Pricing"/>
        <Item href="/admin/returns" label="Returns"/>
        <Item href="/admin/settings" label="Settings"/>
      </nav>
    </aside>
  )
}

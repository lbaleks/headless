'use client';
import React, { useMemo, useState } from 'react'
import Link from 'next/link'
import { useWindowDock } from '@/state/windows'

const BASE_ROUTES = [
  { title:'Dashboard',   href:'/admin/dashboard' },
  { title:'Orders',      href:'/admin/orders' },
  { title:'Products',    href:'/admin/products' },
  { title:'Pricing',     href:'/admin/pricing' },
  { title:'Users',       href:'/admin/users' },
  { title:'Integrations',href:'/admin/integrations' },
  { title:'Flags',       href:'/admin/flags' },
  { title:'Companies',   href:'/admin/companies' },
]

export default function QuickSwitch(){
  // Provider-safe: prøv hooken, men fallback til []
  let wins: { href?: string; title?: string }[] = []
  try {
    const api:any = (useWindowDock as any)?.()
    if (api && Array.isArray(api.windows)) wins = api.windows
  } catch { /* headless fallback */ }

  const [q,setQ] = useState('')

  const data = useMemo(()=>{
    const list = [
      ...wins.map(w=>({ href: w.href || '#', title: w.title || 'Window', kind: 'Open' as const })),
      ...BASE_ROUTES.map(x=>({ href: x.href, title: x.title, kind: 'Route' as const })),
    ]
    const qq = q.trim().toLowerCase()
    return qq
      ? list.filter(x => (x.title||'').toLowerCase().includes(qq) || (x.href||'').toLowerCase().includes(qq))
      : list.slice(0,8)
  },[wins,q])

  // Enkel minimal UI (ikke påtvingende): liten søkeboks + dropdown
  return (
    <div className="relative">
      <input
        className="lb-input text-sm w-64"
        placeholder="Quick switch…"
        value={q}
        onChange={e=>setQ(e.target.value)}
        aria-label="Quick switch search"
      />
      {q && data.length>0 && (
        <div className="absolute mt-1 w-80 max-h-80 overflow-auto bg-white border rounded-lg shadow z-[80]">
          {data.map((x,i)=>(
            <Link key={i} href={x.href} className="flex items-center justify-between px-3 py-2 hover:bg-gray-50 text-sm">
              <span>{x.title}</span>
              <span className="text-xs text-neutral-500">{x.kind}</span>
            </Link>
          ))}
        </div>
      )}
    </div>
  )
}

'use client';
import React from 'react'
import AdminPage from '@/components/AdminPage'
export default function Feeds(){
  const cards=[{t:'Google Shopping',s:'CSV/XML feed'}, {t:'Custom CSV',s:'Schedule & mapping'}, {t:'Marketplace',s:'Coming soon'}]
  return (
    <AdminPage title="Products · Feeds/Channels">
      <div className="grid md:grid-cols-3 gap-4">
        {cards.map((c,i)=>(
          <div key={i} className="lb-card p-4">
            <div className="font-medium">{c.t}</div>
            <div className="lb-muted text-sm">{c.s}</div>
            <button className="mt-3 border rounded px-3 py-1.5">Configure</button>
          </div>
        ))}
      </div>
    </AdminPage>
  )
}

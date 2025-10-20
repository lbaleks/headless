'use client';
import React from 'react'
export function Card({title,actions,children}:{title?:React.ReactNode;actions?:React.ReactNode;children?:React.ReactNode}){
  return (
    <div className="rounded-xl border border-neutral-200 bg-white shadow-sm">
      {(title||actions) && (
        <div className="flex items-center justify-between px-4 py-3 border-b">
          <div className="font-medium">{title}</div>
          <div className="flex items-center gap-2">{actions}</div>
        </div>
      )}
      <div className="p-4">{children}</div>
    </div>
  )
}
export function Section({id,label,children}:{id?:string;label?:string;children?:React.ReactNode}){
  return (
    <section id={id} className="space-y-3">
      {label && <div className="text-xs uppercase tracking-wide text-neutral-500">{label}</div>}
      {children}
    </section>
  )
}

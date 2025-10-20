'use client';
import React from 'react'
export default function Pill({children, tone='neutral'}:{children:React.ReactNode; tone?:'neutral'|'success'|'warn'|'danger'|'info'}){
  const map:any={neutral:'bg-neutral-100 text-neutral-700',success:'bg-green-100 text-green-700',warn:'bg-amber-100 text-amber-800',danger:'bg-red-100 text-red-700',info:'bg-blue-100 text-blue-700'}
  return <span className={"inline-flex items-center px-2 py-0.5 rounded-full text-xs "+(map[tone]||map.neutral)}>{children}</span>
}

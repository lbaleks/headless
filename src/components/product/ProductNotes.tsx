'use client';
import React from 'react'
export default function ProductNotes({value,onChange}:{value:string;onChange:(t:string)=>void}){
  return <textarea className="lb-input w-full h-40" placeholder="Internal notes…" value={value} onChange={e=>onChange(e.target.value)} />
}

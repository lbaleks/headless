'use client';
import * as React from 'react'
export const Field = ({label, children}:{label:string; children:React.ReactNode})=>(
  <div className="admin-section">
    <label className="lb-label">{label}</label>
    {children}
  </div>
)

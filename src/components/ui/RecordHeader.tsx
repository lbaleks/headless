'use client';
import React from 'react'
import Pill from './Pill'
import StageBar from './StageBar'
import { Card } from './Card'
type KPI={ label:string; value:string }
export default function RecordHeader({
  title, subtitle, status, kpis, stages, actions
}:{ title?:string; subtitle?:string; status?:{tone?:'neutral'|'success'|'warn'|'danger'|'info'; text:string}; kpis?:KPI[]; stages?:{id:string;label:string;done?:boolean;current?:boolean}[]; actions?:React.ReactNode }){
  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-4">
        <div>
          <div className="text-2xl font-semibold leading-tight">{title||'Untitled'}</div>
          {subtitle && <div className="text-sm text-neutral-500">{subtitle}</div>}
          {stages && stages.length>0 && <div className="mt-3"><StageBar stages={stages}/></div>}
        </div>
        <div className="flex items-center gap-2">
          {status?.text && <Pill tone={status.tone||'neutral'}>{status.text}</Pill>}
          {actions}
        </div>
      </div>
      {kpis && kpis.length>0 && (
        <Card>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            {kpis.map((k,i)=>(
              <div key={i} className="rounded-lg border p-3">
                <div className="text-xs text-neutral-500">{k.label}</div>
                <div className="text-lg font-semibold">{k.value}</div>
              </div>
            ))}
          </div>
        </Card>
      )}
    </div>
  )
}

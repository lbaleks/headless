"use client";
import useSWR from 'swr'
const fetcher=(u:string)=>fetch(u).then(r=>r.json())
export function ScopeLocalePicker({
  value, onChange
}:{value:{channel:string,locale:string}, onChange:(v:{channel:string,locale:string})=>void}){
  const {data}=useSWR('/api/akeneo/channels', fetcher)
  const channels = data?.channels||[]
  return (
    <div className="flex items-center gap-2 text-sm">
      <select value={value.channel} onChange={e=>onChange({channel:e.target.value, locale:value.locale})}
        className="border rounded px-2 py-1">
        {channels.map((c:any)=><option key={c.code} value={c.code}>{c.label||c.code}</option>)}
      </select>
      <select value={value.locale} onChange={e=>onChange({channel:value.channel, locale:e.target.value})}
        className="border rounded px-2 py-1">
        {(channels.find((c:any)=>c.code===value.channel)?.locales||['nb_NO']).map((l:string)=>
          <option key={l} value={l}>{l}</option>)}
      </select>
    </div>
  )
}

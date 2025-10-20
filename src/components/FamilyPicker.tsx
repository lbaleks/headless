"use client";
import useSWR from 'swr'
const fetcher=(u:string)=>fetch(u).then(r=>r.json())

export default function FamilyPicker({ value, sku }:{ value?:string, sku:string }) {
  const { data } = useSWR('/api/akeneo/families', fetcher)
  const families = data?.families ?? [{code:'default',label:'Default'}]

  async function updateFamily(v:string) {
    await fetch('/api/products/update-family', {
      method:'POST',
      headers:{'content-type':'application/json'},
      body: JSON.stringify({ sku, family:v })
    })
  }

  return (
    <select
      className="border rounded px-1 text-sm"
      defaultValue={value ?? 'default'}
      onChange={e=>updateFamily(e.target.value)}>
      {families.map((f:any)=>(<option key={f.code} value={f.code}>{f.label ?? f.code}</option>))}
    </select>
  )
}

'use client';
import * as React from 'react';
import type { ProductOption } from '@/types/product';

type Props = {
  value: ProductOption[];
  onChange: (next: ProductOption[]) => void;
};

export default function OptionEditor({ value, onChange }: Props) {
  const [rows, setRows] = React.useState<ProductOption[]>(value||[]);
  React.useEffect(()=>setRows(value||[]),[value]);

  const pushBoolean = () => {
    const next=[...rows, {code: crypto.randomUUID(), label:'Ny boolean', type:'boolean', priceDelta:0}];
    setRows(next); onChange(next);
  };
  const pushSelect = () => {
    const next=[...rows, {code: crypto.randomUUID(), label:'Ny select', type:'select', values:[{value:'valg1',label:'Valg 1',priceDelta:0}]}];
    setRows(next); onChange(next);
  };
  const patch = (ix:number, p:Partial<ProductOption>)=>{
    const next=rows.map((r,i)=> i===ix ? {...r, ...p} : r);
    setRows(next); onChange(next);
  };
  const remove = (ix:number)=>{
    const next=rows.filter((_,i)=>i!==ix);
    setRows(next); onChange(next);
  };

  const patchValueRow=(ix:number, vix:number, p: Partial<NonNullable<ProductOption['values']>[number]>)=>{
    const r=rows[ix];
    const vals = Array.isArray(r.values)? r.values.slice() : [];
    vals[vix] = {...vals[vix], ...p};
    patch(ix,{values:vals});
  };
  const addValueRow=(ix:number)=>{
    const r=rows[ix];
    const vals = Array.isArray(r.values)? r.values.slice() : [];
    vals.push({value:`v${vals.length+1}`,label:`Valg ${vals.length+1}`,priceDelta:0});
    patch(ix,{values:vals});
  };
  const removeValueRow=(ix:number,vix:number)=>{
    const r=rows[ix];
    const vals = (r.values||[]).filter((_,i)=>i!==vix);
    patch(ix,{values:vals});
  };

  return (
    <div className="space-y-3">
      <div className="flex gap-2">
        <button onClick={pushBoolean} className="px-3 py-2 text-sm rounded bg-neutral-900 text-white">+ Boolean</button>
        <button onClick={pushSelect} className="px-3 py-2 text-sm rounded border">+ Select</button>
      </div>

      <div className="space-y-4">
        {rows.map((r,ix)=>(
          <div key={r.code} className="p-3 border rounded">
            <div className="flex items-center justify-between">
              <div className="text-sm font-medium">{r.label || '(uten navn)'}</div>
              <button onClick={()=>remove(ix)} className="text-sm text-red-600 hover:underline">Fjern</button>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-4 gap-3 mt-3">
              <div>
                <label className="block text-xs text-neutral-600">Code</label>
                <input className="w-full border rounded px-2 py-1" value={r.code}
                  onChange={e=>patch(ix,{code:e.target.value})}/>
              </div>
              <div>
                <label className="block text-xs text-neutral-600">Label</label>
                <input className="w-full border rounded px-2 py-1" value={r.label}
                  onChange={e=>patch(ix,{label:e.target.value})}/>
              </div>
              <div>
                <label className="block text-xs text-neutral-600">Type</label>
                <select className="w-full border rounded px-2 py-1" value={r.type}
                  onChange={e=>patch(ix,{type:e.target.value as any, ...(e.target.value==='select'?{values:r.values||[]}:{})})}>
                  <option value="boolean">boolean</option>
                  <option value="select">select</option>
                </select>
              </div>

              {r.type==='boolean' && (
                <div>
                  <label className="block text-xs text-neutral-600">Pris-tillegg (true)</label>
                  <input type="number" className="w-full border rounded px-2 py-1"
                    value={Number(r.priceDelta||0)}
                    onChange={e=>patch(ix,{priceDelta:Number(e.target.value)||0})}/>
                </div>
              )}
            </div>

            {r.type==='select' && (
              <div className="mt-3">
                <div className="flex items-center justify-between mb-2">
                  <div className="text-xs text-neutral-600">Verdier</div>
                  <button onClick={()=>addValueRow(ix)} className="text-sm border rounded px-2 py-1">+ verdi</button>
                </div>
                <div className="space-y-2">
                  {(r.values||[]).map((v,vix)=>(
                    <div key={v.value} className="grid grid-cols-1 md:grid-cols-3 gap-2">
                      <input className="border rounded px-2 py-1" placeholder="value" value={v.value}
                        onChange={e=>patchValueRow(ix,vix,{value:e.target.value})}/>
                      <input className="border rounded px-2 py-1" placeholder="label" value={v.label}
                        onChange={e=>patchValueRow(ix,vix,{label:e.target.value})}/>
                      <div className="flex gap-2">
                        <input type="number" className="border rounded px-2 py-1 flex-1" placeholder="pris-delta"
                          value={Number(v.priceDelta||0)}
                          onChange={e=>patchValueRow(ix,vix,{priceDelta:Number(e.target.value)||0})}/>
                        <button onClick={()=>removeValueRow(ix,vix)} className="text-sm text-red-600">Fjern</button>
                      </div>
                    </div>
                  ))}
                  {(!(r.values||[]).length) && <div className="text-xs text-neutral-500">Ingen verdier</div>}
                </div>
              </div>
            )}
          </div>
        ))}
        {(!rows.length) && <div className="text-sm text-neutral-500">Ingen opsjoner lagt til.</div>}
      </div>
    </div>
  );
}

'use client';
import * as React from 'react'
import { Field } from '@/components/ui/Field'
import { slugify } from '@/utils/slug'

export default function ProductSEO({
  value,
  onChange
}:{ value?: any; onChange:(patch:any)=>void }){
  const v = value||{}
  const syncSlug = ()=>{
    if(!v.slug && v.name){
      onChange({ slug: slugify(v.name) })
    }
  }
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
      <Field label="Slug">
        <input className="lb-input" value={v.slug||''}
          onChange={e=>onChange({slug:e.target.value})}
          onBlur={syncSlug}/>
      </Field>
      <Field label="Meta title">
        <input className="lb-input" value={v.metaTitle||''}
          onChange={e=>onChange({metaTitle:e.target.value})}/>
      </Field>
      <div className="md:col-span-2">
        <Field label="Meta description">
          <textarea rows={4} className="lb-input" value={v.metaDescription||''}
            onChange={e=>onChange({metaDescription:e.target.value})}/>
        </Field>
      </div>
    </div>
  )
}

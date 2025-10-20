import * as React from 'react'
import { ScopeLocalePicker } from '@/components/ScopeLocalePicker'
import CompletenessPanel from '@/components/CompletenessPanel'

export const dynamic = 'force-dynamic'

export default function Page() {
  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-semibold">Completeness</h1>
      <p className="text-neutral-600 text-sm">
        Oversikt over produkt-completeness per familie/attributter (Akeneo-inspirert).
      </p>
      <CompletenessPanel />
    </div>
  )
}

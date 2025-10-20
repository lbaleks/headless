export function SourceBadge({ source }: { source?: string }) {
  const c =
    source === 'magento' ? 'bg-indigo-100 text-indigo-700' :
    source === 'local-override' ? 'bg-amber-100 text-amber-700' :
    source === 'local-stub' ? 'bg-rose-100 text-rose-700' :
    'bg-neutral-100 text-neutral-600'
  return <span className={`inline-block rounded px-2 py-0.5 text-xs ${c}`}>{source || 'unknown'}</span>
}

"use client";
import useSWR from 'swr'
import SyncNow from '@/components/SyncNow'
const fetcher=(u:string)=>fetch(u,{cache:'no-store'}).then(r=>r.json())

export default function JobsPanel(){
  const {data, isLoading, mutate} = useSWR('/api/jobs', fetcher, {refreshInterval: 4000})
  const items = data?.items ?? []
  const last = items[0]

  return (
    <div className="p-4 space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold">Jobs</h1>
        <SyncNow />
      </div>

      <div className="rounded-xl border p-4 grid sm:grid-cols-3 gap-4">
        <div>
          <div className="text-sm text-neutral-500">Siste job</div>
          <div className="font-mono">{last?.id ?? '–'}</div>
        </div>
        <div>
          <div className="text-sm text-neutral-500">Startet</div>
          <div className="font-mono">{last?.started ?? '–'}</div>
        </div>
        <div>
          <div className="text-sm text-neutral-500">Ferdig</div>
          <div className="font-mono">{last?.finished ?? '–'}</div>
        </div>
      </div>

      <div className="rounded-xl border overflow-x-auto">
        <table className="min-w-full text-sm">
          <thead className="bg-neutral-50">
            <tr>
              <th className="text-left p-2">ID</th>
              <th className="text-left p-2">Type</th>
              <th className="text-left p-2">Start</th>
              <th className="text-left p-2">Slutt</th>
              <th className="text-left p-2">Counts</th>
            </tr>
          </thead>
          <tbody>
            {items.map((j:any,i:number)=>(
              <tr key={j.id ?? i} className="border-t hover:bg-neutral-50">
                <td className="p-2 font-mono">{j.id}</td>
                <td className="p-2">{j.type}</td>
                <td className="p-2 font-mono">{j.started}</td>
                <td className="p-2 font-mono">{j.finished}</td>
                <td className="p-2 font-mono">
                  {j.counts ? JSON.stringify(j.counts) : '–'}
                </td>
              </tr>
            ))}
            {!items.length && !isLoading && (
              <tr><td colSpan={5} className="p-4 text-neutral-500">Ingen jobber funnet.</td></tr>
            )}
            {isLoading && (
              <tr><td colSpan={5} className="p-4 text-neutral-500">Laster…</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}

 
'use client';
import { useWindowDock } from '@/state/windows'
import { useRouter } from 'next/navigation'
export default function WindowDock(){
  const { wins, focus, close } = useWindowDock()
  const r=useRouter()
  if(!wins?.length) return null
  return (
    <div className="fixed bottom-0 left-0 right-0 z-50 bg-white border-t shadow-inner flex overflow-x-auto px-2 no-scrollbar">
      {wins.map(w=>(
        <button key={w.href}
          onClick={()=>{ focus(w.href); r.push(w.href) }}
          className="flex items-center gap-2 px-3 py-2 m-1 rounded-lg border hover:bg-neutral-50">
          <span className="text-sm truncate">{w.title}</span>
          <span  role="button" tabIndex={0} onKeyDown={(e)=>{if(e.key==="Enter"||e.key===" "){(e.currentTarget as any).click();}}} onClick={e=>{e.stopPropagation(); close(w.href)}} className="text-neutral-400 hover:text-red-500">×</span>
        </button>
      ))}
    </div>
  )
}
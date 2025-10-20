"use client";
import React, { useState, useEffect } from "react";

type Win = { id: string; title: string; href?: string }

export default function DockBar(){
  // Lokal state – vi gjør dock uavhengig av provider
  const [windows, setWindows] = useState<Win[]>([])
  const [collapsed, setCollapsed] = useState(false)

  // Legg til en demo-tab hvis tomt (kan fjernes hvis du ikke vil ha default)
  useEffect(()=>{
    if(windows.length===0){
      setWindows([{id:'dashboard',title:'Dashboard',href:'/admin/dashboard'}])
    }
  },[])

  const ref = React.useRef<HTMLDivElement>(null)
  const updateHeight = React.useCallback(()=>{
    const el = ref.current
    const h = (collapsed? 0 : (el?.offsetHeight||44))
    document.documentElement.style.setProperty('--lb-dock-h', h+'px')
  },[collapsed])

  useEffect(()=>{
    updateHeight()
    const ro = new ResizeObserver(updateHeight)
    if(ref.current) ro.observe(ref.current)
    const onResize = ()=>updateHeight()
    window.addEventListener('resize', onResize)
    return ()=>{ ro.disconnect(); window.removeEventListener('resize', onResize) }
  },[updateHeight])

  const close = (id:string)=> setWindows(prev=>prev.filter(w=>w.id!==id))
  const clear = ()=> setWindows([])

  // Ikke tegn selve baren hvis tom OG collapsed → men behold spacer = 0px
  const showBar = !collapsed && windows.length>0

  return (
    <>
      {showBar && (
        <div ref={ref}
             className="lb-dock fixed inset-x-0 border-b bg-white/90 backdrop-blur z-[90]"
             style={{ top: 'var(--lb-top-nav-h,56px)' }}>
          <div className="max-w-screen-2xl mx-auto px-4">
            <div className="flex items-center justify-between py-2">
              <div className="flex items-center gap-2 overflow-x-auto no-scrollbar">
                {windows.map(w=>(
                  <div key={w.id} className="flex items-center border rounded-lg px-3 py-1.5 bg-white text-sm shadow-sm">
                    <a href={w.href || '#'} className="font-medium">{w.title}</a>
                    <button onClick={()=>close(w.id)}
                      className="ml-2 text-xs text-gray-400 hover:text-red-500" title="Close">×</button>
                  </div>
                ))}
              </div>
              <div className="flex items-center gap-2">
                <button onClick={clear} className="text-xs border rounded px-2 py-1 hover:bg-gray-100">Clear all</button>
                <button onClick={()=>setCollapsed(true)} className="text-xs border rounded px-2 py-1 hover:bg-gray-100" title="Collapse">⌃</button>
              </div>
            </div>
          </div>
        </div>
      )}
      {!showBar && (
        <div className="fixed inset-x-0 z-[90] pointer-events-none"
             style={{ top: 'var(--lb-top-nav-h,56px)' }} aria-hidden="true"></div>
      )}
      {/* Spacer som skyver innholdet ned tilsvarende faktisk dokkhøyde */}
      <div style={{ height: 'var(--lb-dock-h, 0px)' }} aria-hidden="true"></div>

      {/* Liten flytende knapp for å ekspandere når collapsed */}
      {collapsed && (
        <button onClick={()=>{ setCollapsed(false) }}
                className="fixed right-3 z-[91] border rounded px-2 py-1 text-xs bg-white/90 shadow"
                style={{ top: 'calc(var(--lb-top-nav-h,56px) + 6px)' }}
                title="Expand dock">⌄ Dock
        </button>
      )}
    </>
  )
}

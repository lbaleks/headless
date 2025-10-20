"use client";
import React, { createContext, useContext, useMemo, useState, useCallback } from 'react'

export type Win = { id:string; title:string; href?:string }
type DockCtxT = {
  windows: Win[]
  currentId?: string
  open: (w:Win)=>void
  focus: (id:string)=>void
  close: (id:string)=>void
  clear: ()=>void
  registerCurrent: (title:string, href?:string)=>void
}

export const DockCtx = createContext<DockCtxT|null>(null)

export function WindowDockProvider({children}:{children:React.ReactNode}){
  const [windows,setWindows] = useState<Win[]>([])
  const [currentId,setCurrent] = useState<string|undefined>(undefined)

  const open = useCallback((w:Win)=>{
    const id = String(w.id || w.href || Math.random().toString(36).slice(2))
    const title = w.title || 'Window'
    const href = w.href
    setWindows(prev=>{
      const exists=prev.find(x=>x.id===id)
      return exists? prev : [...prev,{id,title,href}]
    })
    setCurrent(id)
  },[])

  const focus = useCallback((id:string)=> setCurrent(id),[])
  const close = useCallback((id:string)=>{
    setWindows(prev=>prev.filter(w=>w.id!==id))
    setCurrent(prev=> prev===id? undefined : prev)
  },[])
  const clear = useCallback(()=>{ setWindows([]); setCurrent(undefined) },[])
  const registerCurrent = useCallback((title:string, href?:string)=>{
    const id = String(href || '/admin')
    setWindows(prev=>{
      const exists = prev.find(w=>w.id===id)
      return exists? prev.map(w=> w.id===id? {...w,title} : w) : [...prev,{id,title,href}]
    })
    setCurrent(id)
  },[])

  const value = useMemo(()=>({windows,currentId,open,focus,close,clear,registerCurrent}),
    [windows,currentId,open,focus,close,clear,registerCurrent])

  return <DockCtx.Provider value={value}>{children}</DockCtx.Provider>
}

export const useWindowDock = ()=>{
  const ctx = useContext(DockCtx)
  if(!ctx) throw new Error('useWindowDock must be used inside WindowDockProvider')
  return ctx
}

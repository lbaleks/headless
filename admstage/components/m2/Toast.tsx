"use client";
import { useEffect } from "react";

export type ToastKind = "success"|"error"|"info"|"warn";
export default function Toast({ kind="info", msg, onDone }:{kind?:ToastKind; msg:string; onDone?:()=>void}) {
  useEffect(()=> {
    const t = setTimeout(()=> onDone?.(), 3000);
    return ()=> clearTimeout(t);
  }, [onDone]);
  const base = "fixed right-4 top-4 px-3 py-2 rounded-lg shadow text-sm";
  const tone = kind==="success" ? "bg-emerald-600 text-white"
    : kind==="error" ? "bg-rose-600 text-white"
    : kind==="warn" ? "bg-amber-500 text-black"
    : "bg-slate-800 text-white";
  return <div className={`${base} ${tone}`}>{msg}</div>;
}

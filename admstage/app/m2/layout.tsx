"use client";
import { useEffect, useState } from "react";
export default function M2Layout({ children }:{children:React.ReactNode}) {
  const [dark, setDark] = useState(false);
  useEffect(()=>{
    document.documentElement.classList.toggle("dark", dark);
  }, [dark]);
  return (
    <div className="min-h-dvh bg-zinc-50 dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100">
      <div className="max-w-5xl mx-auto p-6 space-y-4">
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-semibold">M2 verktøy</h1>
          <label className="text-xs inline-flex items-center gap-2 cursor-pointer">
            <span>Dark</span>
            <input type="checkbox" checked={dark} onChange={e=>setDark(e.target.checked)} />
          </label>
        </div>
        {children}
      </div>
    </div>
  );
}

"use client";
import Image from "next/image";
import { useEffect, useState } from "react";

export default function BrandHeader() {
  const [hasLogo, setHasLogo] = useState(false);
  useEffect(()=>{
    fetch("/brand/logo.png", { method:"HEAD" }).then(r=> setHasLogo(r.ok));
  },[]);
  return (
    <div className="w-full border-b bg-white/70 dark:bg-neutral-900/70 backdrop-blur supports-[backdrop-filter]:bg-white/40 px-4 py-2 flex items-center gap-3">
      {hasLogo ? <Image src="/brand/logo.png" alt="Litebrygg" width={28} height={28}/> :
        <div className="w-7 h-7 rounded bg-neutral-200 dark:bg-neutral-700" />}
      <div className="font-semibold">Litebrygg AS</div>
      <div className="ml-auto text-sm opacity-70">Admin</div>
    </div>
  );
}

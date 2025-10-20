"use client";
export default function Toast({ kind="info", msg }: {kind?: "info"|"ok"|"warn"|"err", msg:string}) {
  const col = kind==="ok" ? "bg-green-600" : kind==="warn" ? "bg-amber-600" : kind==="err" ? "bg-red-600" : "bg-slate-700";
  return (
    <div className={`fixed bottom-4 left-1/2 -translate-x-1/2 text-white px-4 py-2 rounded-lg shadow ${col}`}>
      {msg}
    </div>
  );
}

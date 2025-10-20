"use client";
import { useMemo, useState } from "react";

type Row = Record<string, any>;
export default function DataTable({ rows, columns }:{rows:Row[]; columns:{key:string; label:string}[]}) {
  const [q, setQ] = useState("");
  const [sortKey, setSortKey] = useState<string>(columns[0]?.key||"");
  const [sortDir, setSortDir] = useState<"asc"|"desc">("asc");

  const filtered = useMemo(()=> rows.filter(r =>
    !q || JSON.stringify(r).toLowerCase().includes(q.toLowerCase())
  ), [rows, q]);

  const sorted = useMemo(()=> [...filtered].sort((a,b)=>{
    const av=a[sortKey], bv=b[sortKey];
    if (av==bv) return 0;
    const s = av>bv ? 1 : -1;
    return sortDir==="asc"? s : -s;
  }), [filtered, sortKey, sortDir]);

  return (
    <div className="w-full">
      <div className="flex items-center justify-between gap-2 mb-2">
        <input value={q} onChange={e=>setQ(e.target.value)}
          placeholder="Søk…" className="border rounded-lg px-3 py-2 w-full max-w-sm" />
        <div className="text-xs text-zinc-500">{sorted.length} rader</div>
      </div>
      <div className="overflow-auto rounded-xl border">
        <table className="w-full text-sm">
          <thead className="sticky top-0 bg-white dark:bg-zinc-900">
            <tr>
              {columns.map(c=>(
                <th key={c.key}
                    className="text-left px-3 py-2 border-b cursor-pointer select-none"
                    onClick={()=>{
                      if (sortKey===c.key) setSortDir(d=> d==="asc"?"desc":"asc");
                      else { setSortKey(c.key); setSortDir("asc");}
                    }}>
                  <span className="inline-flex items-center gap-1">
                    {c.label}
                    {sortKey===c.key && <span aria-hidden>{sortDir==="asc"?"▲":"▼"}</span>}
                  </span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {sorted.map((r,i)=>(
              <tr key={i} className="even:bg-black/5/50">
                {columns.map(c=>(
                  <td key={c.key} className="px-3 py-2 border-b">{String(r[c.key] ?? "")}</td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

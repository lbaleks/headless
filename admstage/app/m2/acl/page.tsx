"use client";
import { useEffect, useState } from "react";

type AclItem = { check:string; requires:string; authorized:boolean|null; status:number; note:string };
type AclResp = { ok:boolean; summary:AclItem[]; missing:any[]; unknown:any[] };

const GW = process.env.NEXT_PUBLIC_GATEWAY_BASE || "http://localhost:3044";

export default function AclPage() {
  const [data, setData] = useState<AclResp | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    fetch(`${GW}/ops/acl/check`, { cache: "no-store" })
      .then(r => r.json())
      .then(setData)
      .catch(e => setErr(String(e)));
  }, []);

  return (
    <div className="p-6 space-y-4">
      <h1 className="text-2xl font-bold">🔐 Gateway ACL / Health</h1>
      <div className="text-sm text-neutral-500 dark:text-neutral-400">
        Gateway: <code>{GW}</code>
      </div>
      {err && <div className="text-red-600">Feil: {err}</div>}
      {!data && !err && <div>Laster…</div>}
      {data && (
        <div className="overflow-x-auto">
          <table className="min-w-[640px] text-sm">
            <thead>
              <tr className="text-left border-b">
                <th className="py-2 pr-4">Check</th>
                <th className="py-2 pr-4">Requires</th>
                <th className="py-2 pr-4">Authorized</th>
                <th className="py-2 pr-4">Status</th>
                <th className="py-2 pr-4">Note</th>
              </tr>
            </thead>
            <tbody>
              {data.summary.map((r, i) => (
                <tr key={i} className="border-b last:border-0">
                  <td className="py-2 pr-4">{r.check}</td>
                  <td className="py-2 pr-4">{r.requires}</td>
                  <td className="py-2 pr-4">{String(r.authorized)}</td>
                  <td className="py-2 pr-4">{r.status}</td>
                  <td className="py-2 pr-4">{r.note}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

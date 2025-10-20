"use client";
import useSWR from "swr";
const fetcher = (u:string) => fetch(u).then(r=>r.json());

export default function DevOpsBar(){
  const { data } = useSWR("/api/jobs/latest", fetcher);
  const id = data?.item?.id ?? "—";
  return (
    <div className="text-xs text-neutral-600">
      Last job: <span className="font-mono">{id}</span>
    </div>
  );
}

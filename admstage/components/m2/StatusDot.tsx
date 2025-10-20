export default function StatusDot({ ok, pending, title }:{ ok?:boolean; pending?:boolean; title?:string }) {
  const c = pending ? "bg-amber-400 animate-pulse"
    : ok ? "bg-emerald-500"
    : "bg-rose-500";
  return <span title={title} className={`inline-block w-2.5 h-2.5 rounded-full ${c}`} />;
}

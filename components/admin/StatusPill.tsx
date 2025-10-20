export default function StatusPill({ value }: { value?: string | number }) {
  const v = String(value ?? "").toLowerCase();
  const color =
    v==="complete"||v==="processing" ? "bg-green-100 text-green-700 border-green-200" :
    v==="pending" ? "bg-amber-100 text-amber-700 border-amber-200" :
    v==="canceled" ? "bg-rose-100 text-rose-700 border-rose-200" :
    "bg-neutral-100 text-neutral-700 border-neutral-200";
  return <span className={`inline-block border rounded-full px-2 py-[2px] text-xs ${color}`}>{value ?? "—"}</span>;
}

export default function StatCard({ label, value }:{label:string; value:string|number}) {
  return (
    <div className="rounded-2xl border p-4 shadow-sm bg-white/80 dark:bg-zinc-900/40">
      <div className="text-xs text-zinc-500">{label}</div>
      <div className="text-2xl font-semibold">{value}</div>
    </div>
  );
}

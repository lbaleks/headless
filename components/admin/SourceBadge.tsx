export function SourceBadge({ source }: { source?: string }) {
  const s = String(source || "").toLowerCase();
  const isLocal = s==="local-stub"||s==="local-override";
  const cls = isLocal ? "bg-sky-100 text-sky-700 border-sky-200" : "bg-neutral-100 text-neutral-700 border-neutral-200";
  return <span className={`inline-block border rounded px-2 py-[2px] text-xs ${cls}`}>{source || "magento"}</span>;
}

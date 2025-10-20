export default function BulkPage() {
  return (
    <div className="p-6 space-y-4">
      <h1 className="text-2xl font-bold">📦 Bulk-verktøy (kommer)</h1>
      <p className="text-neutral-600 dark:text-neutral-300">
        Her kommer opplasting av CSV + batch linking/price/stock. Backend-endepunkter er allerede på plass.
      </p>
      <p className="text-sm text-neutral-500">
        Inntil videre: bruk /m2/configurable, /m2/price og /m2/variants for enkeltsaker.
      </p>
    </div>
  );
}

"use client";
import { useEffect, useState } from "react";
import { api } from "../../lib/api";

export default function DashboardPage() {
  const [health, setHealth] = useState<any>(null);
  const [stats, setStats] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const load = async () => {
      try {
        const h = await api.getHealth();
        setHealth(h);
        const s = await api.getStats().catch(() => null);
        setStats(s);
      } catch (err: any) {
        setError(err.message);
      }
    };
    load();
  }, []);

  if (error) return <div className="p-8 text-red-600">❌ {error}</div>;
  if (!health) return <div className="p-8">⏳ Laster dashboard...</div>;

  return (
    <main className="p-8 space-y-8">
      <h1 className="text-3xl font-bold">Litebrygg Admin Dashboard</h1>

      <section className="p-4 bg-gray-50 rounded-lg shadow">
        <h2 className="text-xl font-semibold mb-2">🔗 Gateway / Magento</h2>
        <pre className="text-sm bg-white p-3 rounded">
          {JSON.stringify(health, null, 2)}
        </pre>
      </section>

      {stats && (
        <section className="p-4 bg-gray-50 rounded-lg shadow">
          <h2 className="text-xl font-semibold mb-2">📊 Systemstatistikk</h2>
          <ul className="list-disc pl-6 text-sm">
            <li>Produkter: {stats.products}</li>
            <li>Ordrer: {stats.orders}</li>
            <li>Kunder: {stats.customers}</li>
          </ul>
        </section>
      )}

      {!stats && (
        <div className="text-gray-500 italic">Ingen statistikk tilgjengelig.</div>
      )}
    </main>
  );
}

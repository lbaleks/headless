import Link from "next/link";
export default function Home() {
  return (
    <main className="p-6 space-y-4">
      <h1 className="text-xl font-semibold">Litebrygg – Admin</h1>
      <ul className="list-disc pl-6">
        <li><Link href="/admin/dashboard">Admin Dashboard</Link></li>
        <li><Link href="/admin/products/overview">Products → Overview</Link></li>
        <li><Link href="/api/orders/sync">/api/orders/sync (GET)</Link></li>
        <li><Link href="/api/ai/reco">/api/ai/reco (GET)</Link></li>
      </ul>
    </main>
  );
}

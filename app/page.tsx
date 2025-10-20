import Link from "next/link";
export default function Home() {
  return (
    <main className="min-h-dvh grid place-items-center p-8">
      <div className="text-center space-y-4">
        <h1 className="text-2xl font-semibold">Velkommen 👋</h1>
        <p className="text-sm opacity-70">Gå til admin-dash for å teste</p>
        <p><Link href="/admin/dashboard">Åpne /admin/dashboard</Link></p>
      </div>
    </main>
  );
}
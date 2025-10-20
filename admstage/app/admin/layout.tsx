import Link from "next/link";
export default function AdminLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="p-6">
      <div className="mb-4 flex items-center justify-between">
        <h1 className="text-xl font-semibold">Admin</h1>
        <nav className="space-x-4 text-sm">
          <Link href="/admin/dashboard">Dashboard</Link>
          <Link href="/admin/products/overview">Products</Link>
        </nav>
      </div>
      {children}
    </div>
  );
}
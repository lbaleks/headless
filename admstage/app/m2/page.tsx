import DashboardCard from "@/components/DashboardCard";
import Link from "next/link";

export default function M2Home() {
  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">🛠️ Magento Admin – Verktøykasse</h1>
        <Link href="/" className="text-sm underline">← Hjem</Link>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <DashboardCard
          href="/m2/configurable"
          title="Link configurable"
          desc="Knytt child-variant til parent via attributt/verdi"
          emoji="🔗"
        />
        <DashboardCard
          href="/m2/price"
          title="Sett pris"
          desc="Oppdater pris på gitt SKU"
          emoji="💶"
        />
        <DashboardCard
          href="/m2/variants"
          title="Heal variant"
          desc="Opprett/patch variant og (valgfritt) stock"
          emoji="🩺"
        />
        <DashboardCard
          href="/m2/bulk"
          title="Bulk (coming soon)"
          desc="CSV opplasting for masselinking/price/stock"
          emoji="📦"
        />
        <DashboardCard
          href="/m2/acl"
          title="ACL / Health"
          desc="Sjekk gateway tilkobling og Magento scopes"
          emoji="🩻"
        />
      </div>
    </div>
  );
}

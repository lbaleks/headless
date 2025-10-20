"use client";
import Link from "next/link";

export default function DashboardCard({
  href, title, desc, emoji
}: { href:string; title:string; desc:string; emoji?:string }) {
  return (
    <Link href={href} className="block rounded-2xl border p-4 hover:shadow-md transition">
      <div className="flex items-start gap-3">
        <div className="text-2xl">{emoji ?? "🧩"}</div>
        <div className="flex-1">
          <div className="font-semibold">{title}</div>
          <div className="text-sm text-neutral-500 dark:text-neutral-400">{desc}</div>
        </div>
      </div>
    </Link>
  );
}

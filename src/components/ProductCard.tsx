import Image from "next/image";
import Link from "next/link";
import StockBadge from "./StockBadge";
import { MProduct, imgFrom } from "@/lib/magento";

export default function ProductCard({ p }: { p: MProduct }) {
  const img = imgFrom(p);
  return (
    <Link href={`/product/${encodeURIComponent(p.sku)}`} className="block rounded-2xl border p-3 hover:shadow-sm transition">
      <div className="aspect-square relative rounded-xl overflow-hidden bg-white dark:bg-neutral-900">
        {img ? (
          <Image src={img} alt={p.name} fill sizes="(min-width: 768px) 25vw, 50vw" className="object-contain" />
        ) : (
          <div className="w-full h-full grid place-items-center text-xs opacity-60">Ingen bilde</div>
        )}
      </div>
      <div className="mt-3 flex flex-col gap-1">
        <div className="text-sm font-medium line-clamp-2">{p.name}</div>
        <div className="text-xs opacity-70">{p.sku}</div>
        <div className="flex items-center justify-between mt-1">
          <span className="font-semibold">{p.price != null ? `${p.price.toFixed(2)} kr` : "Pris ukjent"}</span>
          <StockBadge qty={p.extension_attributes?.stock_item?.qty} />
        </div>
      </div>
    </Link>
  );
}

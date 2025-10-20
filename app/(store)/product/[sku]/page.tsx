import Image from "next/image";
import { getProductBySku, imgFrom } from "@/lib/magento";
import VariantSelector from "@/components/VariantSelector";

export default async function ProductPage({ params }: { params: { sku: string }}) {
  const p = await getProductBySku(params.sku);
  const img = imgFrom(p);

  return (
    <div className="grid md:grid-cols-2 gap-8">
      <div className="relative aspect-square rounded-2xl overflow-hidden bg-white dark:bg-neutral-900">
        {img ? <Image src={img} alt={p.name} fill sizes="50vw" className="object-contain" /> : <div className="grid place-items-center opacity-60">Ingen bilde</div>}
      </div>
      <div className="space-y-4">
        <h1 className="text-2xl font-semibold">{p.name}</h1>
        <div className="text-lg font-medium">{p.price != null ? `${p.price.toFixed(2)} kr` : "Pris ukjent"}</div>
        <VariantSelector sku={p.sku} name={p.name} price={p.price} image={img || undefined} />
        <div className="prose dark:prose-invert max-w-none">
          {/* Enkel beskrivelse fra custom_attributes dersom finnes */}
          <p>{p.custom_attributes?.find(a=>a.attribute_code==="description")?.value || "Produktbeskrivelse kommer."}</p>
        </div>
      </div>
    </div>
  );
}

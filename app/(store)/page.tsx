import ProductGrid from "@/components/ProductGrid";

export default function Home() {
  return (
    <div className="space-y-4">
      <h1 className="text-xl font-semibold">Produkter</h1>
      <ProductGrid />
    </div>
  );
}

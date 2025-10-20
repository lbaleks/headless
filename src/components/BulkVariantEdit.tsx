"use client";
import React from 'react';


export function BulkVariantEdit({
  variants,
  onApply
}: {
  variants: any[];
  onApply: (next: any[]) => void;
}) {
  const handleAdd = () => onApply([...variants, { name: 'Ny variant', price: 0, stock: 0 }]);
  const handleRemove = (ix: number) => onApply(variants.filter((_, i) => i !== ix));
  return (
    <div className="space-y-2">
      <div className="flex justify-between items-center">
        <h3 className="font-medium">Varianter</h3>
        <button onClick={handleAdd} className="text-sm px-3 py-1 bg-green-600 text-white rounded">
          Legg til variant
        </button>
      </div>
      {variants.length === 0 && <div className="text-sm text-gray-500">Ingen varianter</div>}
      {variants.map((v, ix) => (
        <div key={ix} className="grid grid-cols-3 gap-2 items-center bg-gray-50 p-2 rounded">
          <input
            className="input"
            value={v.name}
            placeholder="Navn"
            onChange={e => {
              const next = [...variants];
              next[ix].name = e.target.value;
              onApply(next);
            }}
          />
          <input
            type="number"
            className="input"
            value={v.price ?? 0}
            placeholder="Pris"
            onChange={e => {
              const next = [...variants];
              next[ix].price = parseFloat(e.target.value);
              onApply(next);
            }}
          />
          <button
            onClick={() => handleRemove(ix)}
            className="text-xs bg-red-600 text-white rounded px-2 py-1"
          >
            Fjern
          </button>
        </div>
      ))}
    </div>
  );
}

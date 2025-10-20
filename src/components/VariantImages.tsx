"use client";
import React, { useState } from 'react';


export function VariantImages({
  productId,
  variants,
  onChange
}: {
  productId: string;
  variants: any[];
  onChange: (images: any[]) => void;
}) {
  const [files, setFiles] = useState<any[]>([]);

  const handleUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newFiles = Array.from(e.target.files || []);
    setFiles([...files, ...newFiles]);
    safeOnChange([...files, ...newFiles]);
  };

  return (
    <div className="space-y-2">
      <div className="flex justify-between items-center">
        <h3 className="font-medium">Produktbilder</h3>
        <input type="file" multiple onChange={handleUpload} />
      </div>
      <div className="grid grid-cols-4 gap-2">
        {files.map((f, ix) => (
          <div key={ix} className="aspect-square bg-gray-200 flex items-center justify-center text-xs text-gray-600 rounded">
            {f.name || 'Bilde'}
          </div>
        ))}
      </div>
    </div>
  );
}

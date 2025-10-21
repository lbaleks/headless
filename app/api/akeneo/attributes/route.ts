export const runtime = 'nodejs';
import { NextResponse } from 'next/server'

/**
 * Mock: Akeneo attribute-definisjoner per family.
 * Vi returnerer kun det vi trenger for demo (iblandt beer-krav).
 */
export async function GET() {
  return NextResponse.json({
    families: {
      default: { required: ["sku","name","price","status","visibility"] },
      beer:    { required: ["sku","name","price","status","visibility","image","ibu"] }
    },
    // valgfritt: attributter (metadata)
    attributes: {
      image: { type: "media", label: "Bilde" },
      ibu:   { type: "number", label: "IBU"  },
      hops:  { type: "text",   label: "Humle" }
    }
  })
}

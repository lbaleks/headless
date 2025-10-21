// data/pricing.ts
/**
 * Temporary stubs to satisfy imports in API routes.
 * TODO: Replace with real pricing logic or remove the imports where not used.
 */

export type QuoteLine = {
  sku: string
  qty: number
  price?: number
}

/**
 * Simple passthrough for quote calculation placeholder.
 */
export function quoteLine(input: QuoteLine): QuoteLine {
  return input
}

/**
 * Minimal in-memory pricing “database” stub.
 */
export const pricingDB = {
  rules: [] as Array<{ id: string; name: string; match?: unknown; action?: unknown }>,
  lists: [] as Array<{ id: string; name: string; items?: unknown[] }>,
}

console.log("✅ pricing.ts stub loaded");

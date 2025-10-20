export type Variant = {
  id?: string
  key?: string
  label?: string
  sku?: string
  barcode?: string
  multiplier?: number
  priceDelta?: number
  isDefault?: boolean
  image?: string
}
export type PriceTier = { name: string; qtyFrom: number; price: number; currency?: string }
export type Product = {
  id: string
  sku: string
  name: string
  description?: string
  status?: 'active'|'draft'|'archived'|'review'
  category?: string
  price: number
  cost?: number
  stock?: number
  currency?: string
  images?: string[]
  variants?: Variant[]
  priceTiers?: PriceTier[]
  updatedAt?: string
  createdAt?: string
}

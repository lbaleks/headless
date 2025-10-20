export type VariantLike = {
  id?: string | number
  sku?: string
  name?: string
  price?: number
  stock?: number | null
  multiplier?: number | null
  attributes?: Record<string,string>
  // ev. bilde/url/etc.
  imageUrl?: string
}

export type ProductLike = {
  id?: string | number
  sku?: string
  name?: string
  status?: string
  price?: number
  currency?: string
  cost?: number
  stock?: number | null
  variants?: VariantLike[]
  // evt. flere felter (seo, relations, etc.)
}

export const normMult = (m:any)=> {
  const n = Number(m)
  return Number.isFinite(n) && n>0 ? n : 1
}

export const effectiveVariantStock=(prod:ProductLike, v:VariantLike):number=>{
  const m = normMult(v?.multiplier)
  const hasVarStock = v?.stock!==null && v?.stock!==undefined && Number.isFinite(Number(v?.stock))
  const base = Math.max(0, Number(prod?.stock||0))
  if(!hasVarStock){
    // mult=1 -> fullt baselager; mult>1 -> delt på mult
    return Math.max(0, Math.floor(base / (m || 1)))
  }
  return Math.max(0, Number(v?.stock||0))
}

export const effectiveVariantPrice=(prod:ProductLike, v:VariantLike):number=>{
  const base = Number((v?.price ?? prod?.price) ?? 0)
  const mult = normMult(v?.multiplier)
  return base * mult
}

/** Summerer prisjusteringer fra valgte options */
export function applyOptionsPriceDelta(base:number, selected: Array<{priceDelta?:number}>):number{
  const delta = (selected||[]).reduce((a,x)=> a + Number(x?.priceDelta||0), 0)
  return Math.max(0, base + delta)
}

/** True hvis variant kan kjøpes (stock > 0) */
export function variantAvailable(prod:ProductLike, v:VariantLike):boolean{
  return effectiveVariantStock(prod, v) > 0
}

export type Family = {
  code: string
  label?: string
  required_attributes: string[]
  optional_attributes?: string[]
  channels?: { code: string; locales: string[] }[]
}

export function computeCompleteness(
  product: Record<string, any>,
  family: Family
){
  const required = family.required_attributes || []
  const missing: string[] = []
  for(const key of required){
    const v = (product as any)[key]
    const empty = v === null || v === undefined || v === '' || (typeof v==='number' && Number.isNaN(v))
    if (empty) missing.push(key)
  }
  const score = required.length === 0 ? 100 : Math.round(100 * (required.length - missing.length) / required.length)
  return { score, missing, required }
}

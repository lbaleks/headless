
export type RuleType = 'percent_off' | 'fixed_amount' | 'set_price'
export type RuleTarget = 'all' | 'sku' | 'category' | 'brand' | 'query'
export type PricingRule = {
  id: string
  name: string
  type: RuleType
  value: number
  target: RuleTarget
  match?: string
  active?: boolean
  priority?: number
}
export function matches(rule: PricingRule, ctx: { sku?:string; category?:string; brand?:string; query?:string }) {
  if (!rule.active) return false
  switch (rule.target) {
    case 'all': return true
    case 'sku': return !!ctx.sku && !!rule.match && String(ctx.sku).toLowerCase().includes(rule.match.toLowerCase())
    case 'category': return !!ctx.category && !!rule.match && String(ctx.category).toLowerCase().includes(rule.match.toLowerCase())
    case 'brand': return !!ctx.brand && !!rule.match && String(ctx.brand).toLowerCase().includes(rule.match.toLowerCase())
    case 'query': return !!ctx.query && !!rule.match && String(ctx.query).toLowerCase().includes(rule.match.toLowerCase())
    default: return false
  }
}
export function applyRule(price:number, rule:PricingRule){
  if(rule.type==='percent_off') return Math.max(0, price * (1 - rule.value/100))
  if(rule.type==='fixed_amount') return Math.max(0, price - rule.value)
  if(rule.type==='set_price') return Math.max(0, rule.value)
  return price
}
export function applyRules(basePrice:number, rules:PricingRule[], ctx:{ sku?:string; category?:string; brand?:string; query?:string }){
  const active = rules.filter(r=>r.active).sort((a,b)=>(a.priority||0)-(b.priority||0))
  return active.reduce((p,r)=> matches(r,ctx) ? applyRule(p,r) : p, basePrice)
}

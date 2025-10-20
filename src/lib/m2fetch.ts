const BASE = process.env.MAGENTO_BASE_URL || process.env.M2_BASE_URL
const ADM  = process.env.MAGENTO_ADMIN_TOKEN

function ensureEnv() {
  if (!BASE || !ADM) {
    throw new Error('Missing MAGENTO_BASE_URL or MAGENTO_ADMIN_TOKEN in env')
  }
}

type SearchOptions = {
  page?: number
  size?: number
  q?: string
  sort?: string // "created_at:desc" eller "name:asc"
}

export function buildSearchCriteria(opts: SearchOptions = {}) {
  const page = Math.max(1, Number(opts.page || 1))
  const size = Math.max(1, Math.min(200, Number(opts.size || 25)))
  const params: Record<string, string | number> = {
    'searchCriteria[currentPage]': page,
    'searchCriteria[pageSize]': size,
  }

  // sort
  if (opts.sort) {
    const [field, dirRaw] = String(opts.sort).split(':')
    const direction = (dirRaw || 'asc').toUpperCase() === 'DESC' ? 'DESC' : 'ASC'
    params['searchCriteria[sortOrders][0][field]'] = field
    params['searchCriteria[sortOrders][0][direction]'] = direction
  }

  // q (freetext) → enkel or-filter på name/sku/email/firstname/lastname
  if (opts.q && opts.q.trim()) {
    const q = opts.q.trim()
    // NB: Magento støtter OR ved flere filter groups
    // products: name like OR sku like
    params['searchCriteria[filter_groups][0][filters][0][field]'] = 'name'
    params['searchCriteria[filter_groups][0][filters][0][value]'] = `%${q}%`
    params['searchCriteria[filter_groups][0][filters][0][condition_type]'] = 'like'

    params['searchCriteria[filter_groups][1][filters][0][field]'] = 'sku'
    params['searchCriteria[filter_groups][1][filters][0][value]'] = `%${q}%`
    params['searchCriteria[filter_groups][1][filters][0][condition_type]'] = 'like'
  }

  const usp = new URLSearchParams()
  Object.entries(params).forEach(([k, v]) => usp.set(k, String(v)))
  return usp.toString()
}

export async function m2Get<T>(path: string): Promise<T> {
  ensureEnv()
  const base = BASE!.replace(/\/$/, '')
  const url  = `${base}/${path.replace(/^\//, '')}`
  const res  = await fetch(url, {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${ADM}`,
      'Content-Type': 'application/json',
    },
    cache: 'no-store',
  })
  if (!res.ok) {
    let sample: any = {}
    try { sample = await res.json() } catch {}
    throw new Error(`Magento GET ${url} failed: ${res.status} ${JSON.stringify(sample)}`)
  }
  return await res.json()
}

/** Shapere/mapper til et konsistent, lett UI-format */
export function mapProduct(p: any) {
  const findAttr = (code: string) =>
    (p.custom_attributes || []).find((a: any) => a.attribute_code === code)?.value

  return {
    id: p.id,
    sku: p.sku,
    name: p.name,
    type: p.type_id,
    price: p.price,
    status: p.status,
    visibility: p.visibility,
    created_at: p.created_at,
    updated_at: p.updated_at,
    image: findAttr('image') || p.media_gallery_entries?.[0]?.file || null,
    tax_class_id: findAttr('tax_class_id') || null,
    has_options: !!(findAttr('has_options') || p.has_options),
    required_options: !!(findAttr('required_options') || p.required_options),
  }
}

export function mapCustomer(c: any) {
  return {
    id: c.id,
    email: c.email,
    firstname: c.firstname,
    lastname: c.lastname,
    name: [c.firstname, c.lastname].filter(Boolean).join(' '),
    created_at: c.created_at,
    group_id: c.group_id,
    is_subscribed: !!c.extension_attributes?.is_subscribed,
  }
}

export function mapOrder(o: any) {
  return {
    id: o.entity_id,
    increment_id: o.increment_id,
    status: o.status,
    state: o.state,
    created_at: o.created_at,
    updated_at: o.updated_at,
    customer: {
      email: o.customer_email,
      firstname: o.customer_firstname,
      lastname: o.customer_lastname,
      name: [o.customer_firstname, o.customer_lastname].filter(Boolean).join(' '),
    },
    currency: o.order_currency_code || o.base_currency_code,
    totals: {
      grand_total: o.grand_total,
      subtotal: o.subtotal,
      tax: o.tax_amount,
      shipping: o.shipping_amount,
    },
    lines: (o.items || []).map((i: any) => ({
      id: i.item_id,
      sku: i.sku,
      name: i.name,
      qty: i.qty_ordered,
      price: i.price,
      row_total: i.row_total,
      tax_percent: i.tax_percent,
      tax_amount: i.tax_amount,
      product_id: i.product_id,
      type: i.product_type,
    })),
  }
}

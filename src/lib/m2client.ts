// Minimal Magento client uavhengig av annen lokal kode.
const BASE = process.env.MAGENTO_BASE_URL || process.env.M2_BASE_URL
if (!BASE) throw new Error('MAGENTO_BASE_URL (eller M2_BASE_URL) mangler')

function adminToken(): string {
  // Støtt både .env-token og runtime (auto-login) token
  const t = process.env.MAGENTO_ADMIN_TOKEN || (globalThis as any).__M2_TOKEN
  if (!t) throw new Error('MAGENTO_ADMIN_TOKEN er ikke tilgjengelig (prøv å refreshe dev / sjekk /api/_debug/ping)')
  return t
}

export async function m2Get<T>(path: string): Promise<T> {
  const url = `${BASE.replace(/\/+$/,'')}/${path.replace(/^\/+/,'')}`
  const res = await fetch(url, {
    headers: {
      'Authorization': `Bearer ${adminToken()}`,
      'Content-Type': 'application/json',
    },
    // Viktig i Next 15 for å ikke cache admin-lister
    cache: 'no-store',
  })
  if (!res.ok) {
    let body: any = undefined
    try { body = await res.json() } catch {}
    throw new Error(`Magento GET ${url} failed: ${res.status} ${body?JSON.stringify(body):''}`.trim())
  }
  return res.json() as Promise<T>
}

// Små hjelpere for paginering
export function parsePaging(req: Request) {
  const u = new URL(req.url)
  const page = Math.max(1, parseInt(u.searchParams.get('page') || '1', 10))
  const size = Math.max(1, Math.min(200, parseInt(u.searchParams.get('size') || '50', 10)))
  return { page, size }
}

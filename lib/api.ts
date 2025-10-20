export const BASE = process.env.NEXT_PUBLIC_BASE || '';
type Query = Record<string, string | number | boolean | undefined>;
export function qs(q: Query = {}) {
  const u = new URLSearchParams();
  Object.entries(q).forEach(([k, v]) => {
    if (v !== undefined && v !== '') u.set(k, String(v));
  });
  return u.toString();
}
export async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const url = `${BASE}${path}`;
  const r = await fetch(url, {
    cache: 'no-store',
    ...init,
    headers: { 'content-type': 'application/json', ...(init?.headers || {}) },
  });
  if (!r.ok) {
    let d:any=null; try{d=await r.json();}catch{}
    throw new Error(d?.error||d?.message||`HTTP ${r.status} @ ${path}`);
  }
  return r.json() as Promise<T>;
}

import { fetch } from 'undici'
import "../env-load.js"

export const BASE = process.env.M2_BASE_URL || ''
export const TOKEN = process.env.M2_ADMIN_TOKEN || ''

export function ensureEnv() {
  const miss = []
  if (!BASE) miss.push('M2_BASE_URL')
  if (!TOKEN) miss.push('M2_ADMIN_TOKEN (Integration Token)')
  return miss
}

export async function m2Req(method, path, body, headers = {}) {
  const url = `${BASE}${path}`
  const res = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      'Content-Type': 'application/json',
      ...headers
    },
    body: body ? JSON.stringify(body) : undefined
  })
  const text = await res.text()
  let data
  try { data = JSON.parse(text) } catch { data = { raw: text } }
  if (!res.ok) {
    const err = new Error(`Upstream ${res.status}`)
    err.status = res.status
    err.data = data
    throw err
  }
  return data
}

export const m2Get = (p, h) => m2Req('GET', p, null, h)
export const m2Post = (p, b, h) => m2Req('POST', p, b, h)
export const m2Put  = (p, b, h) => m2Req('PUT',  p, b, h)

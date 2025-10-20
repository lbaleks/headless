// Enkel, robust fetch med timeout + JSON-parsing + gode feil
export async function safeFetchJSON<T>(
  input: RequestInfo | URL,
  init: RequestInit & { timeoutMs?: number } = {}
): Promise<{ data?: T; error?: string; status: number }> {
  const { timeoutMs = 15000, ...rest } = init
  const ctrl = new AbortController()
  const t = setTimeout(() => ctrl.abort(), timeoutMs)
  try {
    const res = await fetch(input, {
      cache: 'no-store',
      ...rest,
      signal: ctrl.signal,
      headers: {
        'accept': 'application/json, text/plain, */*',
        ...(rest.headers || {}),
      },
    })
    const status = res.status
    const text = await res.text()
    // Prøv JSON, men ikke kast feil hvis det ikke er gyldig
    let json: any = undefined
    try { json = text ? JSON.parse(text) : undefined } catch {}
    if (!res.ok) {
      return { error: (json && (json.error || json.message)) || `HTTP ${status}`, status }
    }
    return { data: json as T, status }
  } catch (e:any) {
    if (e?.name === 'AbortError') return { error: 'Timeout', status: 0 }
    return { error: e?.message || 'Ukjent feil', status: 0 }
  } finally {
    clearTimeout(t)
  }
}

"use client";

export const GATEWAY =
  process.env.NEXT_PUBLIC_GATEWAY_BASE ||
  process.env.NEXT_PUBLIC_GATEWAY ||
  "http://localhost:3044";

async function handle(res: Response) {
  const text = await res.text();
  let data: any = undefined;
  try { data = text ? JSON.parse(text) : undefined; } catch (_) { /* noop */ }
  if (!res.ok) {
    const msg = data?.error || data?.message || res.statusText || "Request failed";
    throw new Error(typeof msg === "string" ? msg : JSON.stringify(msg));
  }
  return data;
}

export const api = {
  async get(path: string) {
    const url = `${GATEWAY}${path}`;
    const res = await fetch(url, { cache: "no-store" });
    return handle(res);
  },
  async post(path: string, body: any) {
    const url = `${GATEWAY}${path}`;
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    return handle(res);
  },
};

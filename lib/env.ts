export function getMagentoConfig() {
  return {
    baseUrl: (process.env.MAGENTO_URL || process.env.MAGENTO_BASE_URL || '').replace(/\/rest\/?$/,'/rest'),
    adminUser: process.env.MAGENTO_ADMIN_USERNAME || '',
    adminPass: process.env.MAGENTO_ADMIN_PASSWORD || '',
  };
}
export const v1 = (baseUrl: string) => `${baseUrl.replace(/\/$/, '')}/V1`;

export async function getAdminToken(baseUrl: string, user: string, pass: string): Promise<string> {
  if (!baseUrl || !user || !pass) throw new Error('Missing Magento admin creds or baseUrl');
  const res = await fetch(`${v1(baseUrl)}/integration/admin/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: user, password: pass }),
    cache: 'no-store',
  });
  if (!res.ok) {
    const txt = await res.text().catch(()=>res.statusText);
    throw new Error(`Admin token ${res.status}: ${txt}`);
  }
  // Magento returns a JSON string (the token)
  const token = await res.json();
  if (typeof token !== 'string' || !token) throw new Error('Empty admin token');
  return token;
}

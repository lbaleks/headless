/**
 * Simple Role-Based Access Control plugin
 * - GET /v2/auth/whoami   -> identifies current role
 * - GET /v2/auth/roles     -> available roles
 */
const ROLES = {
  admin: { label: 'Administrator', permissions: ['*'] },
  viewer: { label: 'Viewer', permissions: ['read'] },
  sales: { label: 'Sales', permissions: ['orders:view','orders:invoice'] },
  warehouse: { label: 'Warehouse', permissions: ['msi:view','msi:update'] }
}

export default async function rbac(app) {
  app.get('/v2/auth/roles', async () => ({ ok: true, roles: ROLES }))
  app.get('/v2/auth/whoami', async (req) => {
    const h = req.headers || {}
    const role = (h['x-role'] || 'viewer').toString().toLowerCase()
    const info = ROLES[role] ? { key: role, ...ROLES[role] } : { key: 'viewer', ...ROLES.viewer }
    return { ok: true, role: info }
  })
}

// lib/env.ts - herdet env + auth helpers
type MagentoCfg = {
  baseUrl: string;
  token?: string | null;
  adminUser?: string | null;
  adminPass?: string | null;
  preferAdminToken?: boolean;
};
const required = (n:string,v?:string|null)=>{if(!v)throw new Error(`[env] Missing ${n}`);return v};

export function getMagentoConfig(): MagentoCfg {
  const baseUrl = required('MAGENTO_URL',process.env.MAGENTO_URL)?.replace(/\/+$/,'');
  const token=process.env.MAGENTO_TOKEN||null;
  const adminUser=process.env.MAGENTO_ADMIN_USERNAME||null;
  const adminPass=process.env.MAGENTO_ADMIN_PASSWORD||null;
  const preferAdminToken=(process.env.MAGENTO_PREFER_ADMIN_TOKEN??'1')!=='0';
  if(!token && (!adminUser||!adminPass))
    throw new Error('[env] Provide MAGENTO_TOKEN or MAGENTO_ADMIN_USERNAME+MAGENTO_ADMIN_PASSWORD');
  return{baseUrl,token,adminUser,adminPass,preferAdminToken};
}
export function v1(b:string){return`${b.replace(/\/+$/,'')}/V1`;}
export async function getAdminToken(b:string,u?:string|null,p?:string|null){
  if(!u||!p)throw new Error('[env] Missing admin creds');
  const r=await fetch(`${v1(b)}/integration/admin/token`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:u,password:p}),cache:'no-store'});
  if(!r.ok)throw new Error(`[env] token fail ${r.status}`);
  return(await r.text()).replace(/^"+|"+$/g,'');
}
export async function authHeader(cfg:MagentoCfg){
  if(cfg.preferAdminToken && cfg.adminUser && cfg.adminPass){
    const jwt=await getAdminToken(cfg.baseUrl,cfg.adminUser,cfg.adminPass);
    return{Authorization:`Bearer ${jwt}`};
  }
  if(cfg.token)return{Authorization:`Bearer ${cfg.token}`};
  const jwt=await getAdminToken(cfg.baseUrl,cfg.adminUser!,cfg.adminPass!);
  return{Authorization:`Bearer ${jwt}`};
}

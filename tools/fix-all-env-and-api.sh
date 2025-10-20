#!/usr/bin/env bash
set -euo pipefail
echo "⚙️  Oppdaterer env-guards, API-ruter og scripts for IBU/SRM/HOP/MALT ..."

ROOT="$(pwd)"
mkdir -p "$ROOT/tools" "$ROOT/app/api/products"
cd "$ROOT"

### 1. lib/env.ts
cat > lib/env.ts <<'TS'
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
TS

### 2. api routes
mkdir -p app/api/products/[sku]
cat > app/api/products/[sku]/route.ts <<'TS'
import { NextResponse } from 'next/server';
import { getMagentoConfig, v1, authHeader } from '@/lib/env';
export const runtime='nodejs'; export const revalidate=0;
type Attr={attribute_code:string;value:any}; type M2={sku?:string;custom_attributes?:Attr[]|null};
const IBU_ALIASES=['ibu','ibu2'] as const;
const lift=(p:M2)=>{const ca=Array.isArray(p?.custom_attributes)?p!.custom_attributes!:[];const attrs=Object.fromEntries(ca.map(x=>[x.attribute_code,x.value]));const pick=(a:readonly string[])=>a.map(k=>attrs[k]).find(v=>v!=null)??null;return{...(p||{}),ibu:pick(IBU_ALIASES),srm:attrs['srm']??null,hop_index:attrs['hop_index']??null,malt_index:attrs['malt_index']??null,_attrs:attrs}};
export async function GET(_:Request,c:{params:{sku:string}}){
 try{
  const {sku}=c.params;const cfg=getMagentoConfig();const headers=await authHeader(cfg);
  const url=`${v1(cfg.baseUrl)}/products/${encodeURIComponent(sku)}?storeId=0`;
  const r=await fetch(url,{headers,cache:'no-store'});
  if(!r.ok)return NextResponse.json({error:`Magento ${r.status}`},{status:500});
  const d:M2=await r.json();return NextResponse.json(lift(d));
 }catch(e:any){return NextResponse.json({error:e?.message||String(e)},{status:500});}
}
TS

cat > app/api/products/merged/route.ts <<'TS'
import { NextResponse } from 'next/server';
import { getMagentoConfig, v1, authHeader } from '@/lib/env';
export const runtime='nodejs'; export const revalidate=0;
type Attr={attribute_code:string;value:any}; type M2={sku?:string;custom_attributes?:Attr[]|null};
const IBU_ALIASES=['ibu','ibu2'] as const;
const lift=(p:M2)=>{const ca=Array.isArray(p?.custom_attributes)?p!.custom_attributes!:[];const attrs=Object.fromEntries(ca.map(x=>[x.attribute_code,x.value]));const pick=(a:readonly string[])=>a.map(k=>attrs[k]).find(v=>v!=null)??null;return{...(p||{}),ibu:pick(IBU_ALIASES),srm:attrs['srm']??null,hop_index:attrs['hop_index']??null,malt_index:attrs['malt_index']??null,_attrs:attrs}};
export async function GET(req:Request){
 try{
  const {searchParams}=new URL(req.url);const page=Number(searchParams.get('page')||'1')||1;const size=Number(searchParams.get('size')||'50')||50;
  const cfg=getMagentoConfig();const headers=await authHeader(cfg);
  const list=`${v1(cfg.baseUrl)}/products?searchCriteria[current_page]=${page}&searchCriteria[page_size]=${size}&storeId=0`;
  const res=await fetch(list,{headers,cache:'no-store'});if(!res.ok)return NextResponse.json({error:`Magento ${res.status}`},{status:500});
  const data=await res.json();let items:Array<M2>=Array.isArray(data?.items)?data.items:[];
  let lifted=items.map(lift);
  const need=lifted.filter(p=>!p.ibu||p.srm==null||p.hop_index==null||p.malt_index==null);
  if(need.length){const {default:pLimit}=await import('p-limit');const limit=pLimit(5);
    const det=await Promise.all(need.map(p=>limit(async()=>{const u=`${v1(cfg.baseUrl)}/products/${encodeURIComponent(p.sku||'')}?storeId=0`;const r=await fetch(u,{headers,cache:'no-store'});if(!r.ok)return p;const d:M2=await r.json();return lift(d);})));
    const m=new Map(det.map(d=>[d.sku,d]));lifted=lifted.map(p=>m.get(p.sku!)??p);
  }
  return NextResponse.json({items:lifted,page,size,total:data?.total_count??lifted.length});
 }catch(e:any){return NextResponse.json({error:e?.message||String(e)},{status:500});}
}
TS

### 3. scripts
cat > tools/beer-metrics-autoinstall-fix.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
find_group_id(){
 local setId="$1" wanted="${2:-General}"
 local groups gid
 groups="$(curl -sS -H "Authorization: Bearer $JWT" "$V1/products/attribute-sets/$setId/groups")"
 gid="$(jq -re '.[]?|select(.attribute_group_name=="'"$wanted"'")?.attribute_group_id'<<<"$groups"2>/dev/null||true)"
 if [[ -z "$gid"||"$gid"=="null" ]];then gid="$(jq -re '.[0]?.attribute_group_id'<<<"$groups"2>/dev/null||true)";fi
 if [[ -z "$gid"||"$gid"=="null" ]];then echo "❌ Ingen groupId for $setId">&2;exit 1;fi
 echo "$gid"
}
echo "✓ Patch klar. Sett LC_ALL=C og kall find_group_id i scriptet ditt."
SH

cat > tools/ibu-backfill.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
BASE="http://localhost:3000"; SIZE=200; PAGE=1; patched=0
while :;do
 json="$(curl -s "$BASE/api/products/merged?page=$PAGE&size=$SIZE")"
 count="$(jq -r '.items|length'<<<"$json")";[[ "$count" -gt 0 ]]||break
 echo "🔎 Side $PAGE ($count produkter)…"
 echo "$json"|jq -c '.items[]|{sku,ibu,ibu2:(._attrs.ibu2//null)}'|while read -r row;do
  sku="$(jq -r '.sku'<<<"$row")";ibu="$(jq -r '.ibu'<<<"$row")";ibu2="$(jq -r '.ibu2'<<<"$row")"
  if [[ "$ibu"=="null" && "$ibu2"!="null" ]];then
    echo "✍️  $sku: setter ibu=$ibu2 (fra ibu2)"
    curl -s -X PATCH "$BASE/api/products/update-attributes" -H 'Content-Type: application/json' \
      --data "{\"sku\":\"$sku\",\"attributes\":{\"ibu\":\"$ibu2\"}}" >/dev/null
    patched=$((patched+1))
  fi
 done
 PAGE=$((PAGE+1))
done
echo "✅ Ferdig. Oppdaterte $patched produkter."
SH

cat > tools/ibu-smoke.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
BASE="http://localhost:3000"; SKU="${1:-TEST-RED}"; VAL="${2:-42}"
echo "✍️  PATCH $SKU.ibu=$VAL"
curl -s -X PATCH "$BASE/api/products/update-attributes" -H 'Content-Type: application/json' \
  --data "{\"sku\":\"$SKU\",\"attributes\":{\"ibu\":\"$VAL\"}}" >/dev/null
echo "🔎 SINGLE"; curl -s "$BASE/api/products/$SKU"|jq '{sku,ibu,srm,hop_index,malt_index,_attrs:{ibu:._attrs.ibu,ibu2:._attrs.ibu2}}'
echo "🔎 MERGED"; curl -s "$BASE/api/products/merged?page=1&size=50"|jq '.items[]?|select(.sku=="'"$SKU"'")|{sku,ibu,srm,hop_index,malt_index,_attrs:{ibu:._attrs.ibu,ibu2:._attrs.ibu2}}'
SH

chmod +x tools/*.sh

### 4. installer p-limit
pnpm add p-limit -w || npm install p-limit

echo "✅ Alt oppdatert. Kjør 'pnpm dev' og test:"
echo "   tools/ibu-smoke.sh TEST-RED 42"
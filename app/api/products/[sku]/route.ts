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

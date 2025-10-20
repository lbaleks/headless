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

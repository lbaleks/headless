import type { NextApiRequest, NextApiResponse } from 'next'
function base(){const b=(process.env.MAGENTO_BASE_URL||process.env.M2_BASE_URL||process.env.NEXT_PUBLIC_GATEWAY_BASE||'').replace(/\/+$/,'');return b? (b.endsWith('/rest')?b:`${b}/rest`):''}
function token(){return (process.env.MAGENTO_ADMIN_TOKEN||process.env.M2_ADMIN_TOKEN||process.env.M2_TOKEN)||''}
async function tryFetch(path:string){
  const B=base(), T=token()
  if(!B||!T) return {ok:false,status:0,url:B?`${B}/${path}`:path,error:'missing env'}
  const url=`${B}/${path}`
  const rsp=await fetch(url,{headers:{Authorization:`Bearer ${T}`}})
  const text=await rsp.text()
  let json:any=null; try{json=JSON.parse(text)}catch{}
  return {ok:rsp.ok,status:rsp.status,url,sample: json ?? (text.slice(0,200)+(text.length>200?'…':''))}
}
export default async function handler(_req:NextApiRequest,res:NextApiResponse){
  const B=base(), T=token()
  const checks=await Promise.all([
    tryFetch('V1/orders?searchCriteria[pageSize]=1'),
    tryFetch('V1/products?searchCriteria[pageSize]=1'),
    tryFetch('V1/customers/search?searchCriteria[pageSize]=1'),
  ])
  res.status(200).json({ base:B, tokenPrefix: T?T.slice(0,8)+'…':null, checks })
}

import type { NextApiRequest, NextApiResponse } from 'next'
export default function handler(_req:NextApiRequest,res:NextApiResponse){
  const base=(process.env.MAGENTO_BASE_URL||process.env.M2_BASE_URL||process.env.NEXT_PUBLIC_GATEWAY_BASE)||''
  const token=(process.env.MAGENTO_ADMIN_TOKEN||process.env.M2_ADMIN_TOKEN||process.env.M2_TOKEN)||''
  res.status(200).json({ ok:Boolean(base&&token), hasBase:!!base, hasToken:!!token, base, tokenPrefix: token?token.slice(0,8)+'…':null })
}

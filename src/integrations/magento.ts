export async function magentoPing(){
  const base=process.env.MAGENTO_BASE_URL, token=process.env.MAGENTO_TOKEN
  if(!base||!token) return { ok:false, error:'Missing MAGENTO_BASE_URL / MAGENTO_TOKEN' }
  return { ok:true }
}

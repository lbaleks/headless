export async function call(path:string, init?:RequestInit){
  const r = await fetch(path, { cache:'no-store', ...init, headers:{'content-type':'application/json', ...(init?.headers||{})}});
  let data:any=null; try{ data = await r.json(); }catch{}
  if(!r.ok) throw new Error(data?.error||`HTTP ${r.status}`);
  return data;
}

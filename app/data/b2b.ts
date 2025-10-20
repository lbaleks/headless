// app/data/b2b.ts
export type Company = { id:string; name:string; priceTier?: "A"|"B"|"C"; role?: "admin"|"ops"|"support"|"viewer" };
export type User    = { id:string; name:string; email:string; companyId?:string; role?: "admin"|"ops"|"support"|"viewer" };

const mem = global as any;
if (!mem.__B2B__) {
  mem.__B2B__ = {
    companies: [
      { id:"litebrygg", name:"LiteBrygg AS", priceTier:"A", role:"admin" },
      { id:"kafe-sol",  name:"Kafé Sol",     priceTier:"B", role:"viewer" }
    ] as Company[],
    users: [
      { id:"alex",  name:"Aleksander", email:"alex@example.com",  companyId:"litebrygg", role:"admin" },
      { id:"maria", name:"Maria",      email:"maria@kafe-sol.no", companyId:"kafe-sol",  role:"viewer" }
    ] as User[]
  };
}
export const db:{ companies:Company[]; users:User[] } = mem.__B2B__;

export function upsertCompany(c:Company){
  const i = db.companies.findIndex(x=>x.id===c.id);
  if(i>=0) db.companies[i] = { ...db.companies[i], ...c }; else db.companies.push(c);
  return c;
}
export function upsertUser(u:User){
  const i = db.users.findIndex(x=>x.id===u.id);
  if(i>=0) db.users[i] = { ...db.users[i], ...u }; else db.users.push(u);
  return u;
}

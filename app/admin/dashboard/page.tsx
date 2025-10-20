import SyncButtons from "@/components/admin/SyncButtons";
import DevOpsBar from "@/components/admin/DevOpsBar";

async function fetchJson<T>(path:string):Promise<T>{
  const r = await fetch(path, { cache: "no-store" });
  if(!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.json() as Promise<T>;
}

type ListResp<T> = { total:number; items:T[] };

export default async function Dashboard(){
  const [prods, custs, ords] = await Promise.all([
    fetchJson<ListResp<any>>("/api/products?page=1&size=1").catch(()=>({total:0,items:[]})),
    fetchJson<ListResp<any>>("/api/customers?page=1&size=1").catch(()=>({total:0,items:[]})),
    fetchJson<ListResp<any>>("/api/orders?page=1&size=1").catch(()=>({total:0,items:[]})),
  ]);

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <Card title="Products" value={prods.total}/>
        <Card title="Customers" value={custs.total}/>
        <Card title="Orders" value={ords.total}/>
      </div>

      <section className="space-y-2">
        <h2 className="text-sm font-medium text-neutral-700">Sync</h2>
        <SyncButtons />
      </section>

      <section className="space-y-2">
        <h2 className="text-sm font-medium text-neutral-700">Dev data</h2>
        <DevOpsBar />
      </section>

      <section className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <MiniList title="Latest product" rows={prods.items.map(p=>({a:p.sku, b:p.name, c:p.source}))} />
        <MiniList title="Latest customer" rows={custs.items.map(c=>({a:c.id, b:c.email, c:c.source}))} />
        <MiniList title="Latest order" rows={ords.items.map(o=>({a:o.id, b:o.status, c:o.source}))} />
      </section>
    </div>
  );
}

function Card({title,value}:{title:string; value:number}){
  return (
    <div className="border rounded-2xl bg-white px-4 py-5">
      <div className="text-sm text-neutral-500">{title}</div>
      <div className="text-3xl font-semibold mt-1">{value ?? 0}</div>
    </div>
  );
}
function MiniList({title,rows}:{title:string; rows:{a:any,b:any,c:any}[]}){
  return (
    <div className="border rounded-2xl bg-white overflow-hidden">
      <div className="px-4 py-2 text-sm font-medium border-b bg-neutral-50">{title}</div>
      <div className="divide-y">
        {rows.length===0 && <div className="px-4 py-3 text-sm text-neutral-500">—</div>}
        {rows.map((r,i)=>(
          <div key={i} className="px-4 py-3 text-sm flex items-center gap-3">
            <div className="w-28 text-neutral-500 truncate">{String(r.a)}</div>
            <div className="flex-1 truncate">{String(r.b)}</div>
            <div className="text-xs border rounded px-2 py-[2px] bg-neutral-100">{String(r.c||"")}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

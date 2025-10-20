export type Lot = { lotId:string; qty:number; expiry?:string|null };
export type Strategy = "FIFO"|"FEFO";

/** sorter partier etter strategi (FIFO=oldest created first; FEFO=closest expiry first) */
export function sortLots(strategy:Strategy, lots:Lot[]): Lot[] {
  const copy = [...(lots||[])];
  if (strategy==="FEFO") {
    return copy.sort((a,b)=>{
      const ea = a.expiry ? Date.parse(a.expiry) : Number.POSITIVE_INFINITY;
      const eb = b.expiry ? Date.parse(b.expiry) : Number.POSITIVE_INFINITY;
      return ea - eb;
    });
  }
  // FIFO: antar lotId (eller naturlig rekkefølge) representerer *eldst først* hvis vi har createdAt etc.
  return copy; // already in received order
}

/** fordel ønsket qty over lots etter strategi */
export function allocate(strategy:Strategy, lots:Lot[], want:number){
  const res:{ lotId:string; take:number }[] = [];
  let left = Math.max(0, want|0);
  for (const l of sortLots(strategy, lots)) {
    if (left<=0) break;
    const take = Math.min(l.qty|0, left);
    if (take>0) { res.push({ lotId:l.lotId, take }); left -= take; }
  }
  return { allocations: res, requested: want, fulfilled: want-left, remaining: left };
}

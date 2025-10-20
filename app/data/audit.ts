// app/data/audit.ts
export type AuditEvent = {
  id:string; ts:number; actor?:string; action:string; target?:string; meta?:any;
};

const mem = global as any;
if (!mem.__AUDIT__) { mem.__AUDIT__ = { events: [] as AuditEvent[] }; }
export const auditDB:{ events:AuditEvent[] } = mem.__AUDIT__;

export function append(ev:Omit<AuditEvent,"id"|"ts">){
  const id = "evt_"+(auditDB.events.length+1);
  const row:AuditEvent = { id, ts: Date.now(), ...ev };
  auditDB.events.unshift(row);       // nyeste først
  auditDB.events = auditDB.events.slice(0,5000); // begrens
  return row;
}

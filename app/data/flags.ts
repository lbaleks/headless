// app/data/flags.ts
export type FlagKey =
  | "pricing:bulk-discount"
  | "dashboard:show-inventory"
  | "orders:auto-export";

export type Flag = { key:FlagKey; on:boolean; note?:string };

const mem = global as any;
if (!mem.__FLAGS__) {
  mem.__FLAGS__ = {
    flags: [
      { key:"pricing:bulk-discount", on:true,  note:"Aktiver ekstra volumrabattlogikk" },
      { key:"dashboard:show-inventory", on:true, note:"Vis lagerpanel i dashboard" },
      { key:"orders:auto-export", on:false, note:"Eksporter ordre automatisk" },
    ] as Flag[],
  };
}
export const flagsDB:{ flags:Flag[] } = mem.__FLAGS__;

export function getFlags():Flag[]{ return flagsDB.flags.slice(); }
export function setFlags(next:Flag[]){ flagsDB.flags = next; return getFlags(); }

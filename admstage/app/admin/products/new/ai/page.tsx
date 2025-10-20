"use client";
import { useEffect, useMemo, useState } from "react";

const HOPS_CLASSIC = ["East Kent Goldings","Fuggles","Saaz","Hallertau Mittelfrüh","Tettnang","Perle"];
const HOPS_MODERN  = ["Citra","Mosaic","Simcoe","Nelson Sauvin","Motueka","Amarillo","Galaxy"];
const STYLES       = ["Pilsner","Lager","IPA","Pale Ale","Stout","Porter","Saison","Wit","Bock","Sour"];

function hash32(s: string){let h=2166136261>>>0;for(let i=0;i<s.length;i++){h^=s.charCodeAt(i);h=Math.imul(h,16777619);}return h>>>0;}
function rngFrom(seed:number){return function(){seed|=0;seed=seed+0x6D2B79F5|0;let t=Math.imul(seed^seed>>>15,1|seed);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296;};}
function fyPick<T>(arr:T[], count:number, rng:()=>number){
  const a=[...arr]; for(let i=a.length-1;i>0;i--){const j=Math.floor(rng()*(i+1)); [a[i],a[j]]=[a[j],a[i]];} return a.slice(0,count);
}

function extract(prompt: string){
  const p = prompt.toLowerCase();
  const styleHints: Record<string,string> = {
    "stout":"Stout","porter":"Porter","pils":"Pilsner","pilsner":"Pilsner",
    "ipa":"IPA","lager":"Lager","saison":"Saison","wit":"Wit","bock":"Bock","sour":"Sour","sur":"Sour"
  };
  const key = Object.keys(styleHints).find(k=>p.includes(k));
  const styleName = key ? styleHints[key] : (STYLES.find(s=>p.includes(s.toLowerCase())) || "Pale Ale");
  const dark = /mørk|mork|svart|sort|dark|roast|ristet/.test(p);
  const coffee = /kaffe|coffee|espresso|kakao|sjokolade|chocolate|cacao/.test(p);
  const fruity = /frukt|fruity|tropisk|citrus|grapefrukt|appelsin|apelsin|sitron|lime|ananas|mango|passion/.test(p);
  const bitterUp = /bitter|tørr|torr|resin|harpiks/.test(p);
  const smooth   = /myk|smooth|rund|silky|fløyel|flott/.test(p);
  const session  = /session|lett|lav|low/.test(p);
  const imperial = /imperial|dobbel|double|sterk|barrel|fatlag/.test(p);
  const hopAll = [...HOPS_CLASSIC, ...HOPS_MODERN].map(h=>h.toLowerCase());
  const hopMention = hopAll.find(h => p.includes(h));
  return { styleName, dark, coffee, fruity, bitterUp, smooth, session, imperial, hopMention };
}

function pickHop(rng: ()=>number, f: ReturnType<typeof extract>){
  if (f.hopMention) return f.hopMention.split(" ").map(w=>w[0]?w[0].toUpperCase()+w.slice(1):w).join(" ");
  if (f.styleName==="Stout" || f.styleName==="Porter") return HOPS_CLASSIC[Math.floor(rng()*HOPS_CLASSIC.length)];
  if (f.styleName==="Pilsner" || f.styleName==="Lager" || f.styleName==="Bock"){
    const pool = ["Hallertau Mittelfrüh","Tettnang","Saaz","Perle"]; return pool[Math.floor(rng()*pool.length)];
  }
  const pool = f.fruity ? HOPS_MODERN : [...HOPS_CLASSIC, ...HOPS_MODERN];
  return pool[Math.floor(rng()*pool.length)];
}

function spec(rng: ()=>number, f: ReturnType<typeof extract>){
  let abv = 5.0, ibu = 25, srm = 6;
  switch (f.styleName) {
    case "Stout":  abv=5.0+rng()*1.2; ibu=30+rng()*20; srm=30+rng()*10; break;
    case "Porter": abv=5.2+rng()*1.0; ibu=25+rng()*20; srm=25+rng()*10; break;
    case "Pilsner":abv=4.5+rng()*0.7; ibu=25+rng()*15; srm=3+rng()*2;   break;
    case "Lager":  abv=4.6+rng()*0.9; ibu=18+rng()*12; srm=4+rng()*5;   break;
    case "IPA":    abv=5.8+rng()*1.4; ibu=45+rng()*35; srm=6+rng()*6;   break;
    case "Saison": abv=5.5+rng()*1.0; ibu=22+rng()*18; srm=4+rng()*6;   break;
    case "Wit":    abv=4.7+rng()*0.6; ibu=12+rng()*8;  srm=3+rng()*3;   break;
    case "Bock":   abv=6.2+rng()*1.0; ibu=20+rng()*15; srm=12+rng()*10; break;
    case "Sour":   abv=4.0+rng()*1.0; ibu=5+rng()*10;  srm=3+rng()*5;   break;
  }
  if (f.dark)   srm = Math.max(srm, 28 + Math.round(rng()*10));
  if (f.coffee) srm = Math.max(srm, 30 + Math.round(rng()*8));
  if (f.session){ abv = Math.min(abv, 4.2 + rng()*0.5); ibu = Math.max(ibu-10, 12); }
  if (f.imperial){ abv = Math.max(abv, 7.5 + rng()*1.0); ibu = Math.max(ibu, 50 + Math.round(rng()*30)); }
  if (f.fruity)  ibu = Math.max(ibu, 22 + Math.round(rng()*18));
  if (f.bitterUp) ibu = Math.max(ibu, 40 + Math.round(rng()*25));
  if (f.smooth)  ibu = Math.min(ibu, 28 + Math.round(rng()*10));
  return { abv:+abv.toFixed(1), ibu:Math.round(ibu), srm:Math.round(srm) };
}

function makeVariants(prompt:string){
  const seed = hash32(prompt.trim().toLowerCase());
  const rng = rngFrom(seed);
  const f = extract(prompt);
  const hop = pickHop(rng, f);
  const { abv, ibu, srm } = spec(rng, f);
  const year = new Date().getFullYear();

  const maltsDark  = ["Pilsnermalt","Münchener","Sjokolademalt","Ristet bygg","Carafa","Carapils"];
  const maltsPale  = ["Pilsnermalt","Pale Ale","Maris Otter","Havre","Hvete","Carapils","Light Crystal"];
  const useDark = f.styleName==="Stout" || f.styleName==="Porter" || f.dark || f.coffee;
  const yeastDark  = ["S-04","Nottingham","Irish Ale"];
  const yeastPale  = ["US-05","W34/70","Kveik","Abbey","Saison Dupont"];
  const yeast = (useDark?yeastDark:yeastPale)[Math.floor(rng()*(useDark?yeastDark.length:yeastPale.length))];
  const malts = fyPick(useDark?maltsDark:maltsPale, 3, rng);

  const baseDesc =
    f.coffee
      ? `Mørk ${f.styleName.toLowerCase()} med kaffe/ristede toner, brygget med ${hop}, ${malts[0]} og ${yeast}. Balansert profil, ${ibu} IBU og ${abv}% ABV.`
      : `En ${f.styleName.toLowerCase()} brygget med ${hop}, ${malts[0]} og ${yeast}. Profil: ${ibu} IBU og ${abv}% ABV.`;

  const v1 = { name: `${f.styleName} – ${hop}`, description: baseDesc,
    attributes:{style:f.styleName, hop, abv, ibu, srm, yeast, malt:malts} };
  const v2 = { name: `${f.styleName} ${hop} ${year}`,
    description: baseDesc + " Årets batch med justert humleprofil.",
    attributes:{...v1.attributes, abv: +(abv+0.2).toFixed(1), ibu: Math.max(ibu-2, 5)} };
  const v3 = { name: `${f.styleName} ${hop} Small Batch No.${100+Math.floor(rng()*900)}`,
    description: baseDesc + " Begrenset volum, serveres 6–8 °C.",
    attributes:{...v1.attributes, abv: +(abv-0.2).toFixed(1), ibu: Math.max(ibu-5, 5)} };
  return [v1,v2,v3];
}

export default function AIProductPage(){
  async function saveDraft(d:any){ await fetch("/api/draft",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(d)}); }

  const [prompt,setPrompt]=useState("");
  const [mounted,setMounted]=useState(false);
  useEffect(()=>{ setMounted(true); },[]);
  const variants = useMemo(()=> mounted ? makeVariants(prompt||"Ny øl") : [], [mounted,prompt]);

  async function sendDraft(v:any){
    try{
      const res = await fetch("/api/draft",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(v)});
      const j=await res.json();
      alert(j.ok ? "Produktutkast opprettet (lokal stub)" : ("Feil: "+(j.error||"ukjent")));
    }catch(e:any){ alert("Feil: "+e.message); }
  }

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">🧪 AI-produktmotor</h1>
      <p className="text-sm opacity-80">Skriv stikkord, f.eks. "stout kaffe mørk", "pils saaz ren", "ipa tropisk bitter".</p>

      <input
        value={prompt}
        onChange={e=>setPrompt(e.target.value)}
        placeholder="Eks: stout kaffe mørk"
        className="border rounded px-3 py-2 w-full max-w-xl"
      />

      {!mounted ? <div className="opacity-60 text-sm">Laster forslag…</div> : (
        <div className="grid sm:grid-cols-3 gap-3">
          {variants.map((v,i)=>(
            <div key={i} className="border rounded p-3 space-y-2">
              <div className="font-semibold">{v.name}</div>
              <div className="text-sm opacity-80">{v.description}</div>
              <div className="text-xs opacity-70">ABV {v.attributes.abv}% · IBU {v.attributes.ibu} · SRM {v.attributes.srm}</div>
              <div className="text-xs opacity-70">Humle: {v.attributes.hop}</div>
              <div className="text-xs opacity-70">Gjær: {v.attributes.yeast}</div>
              <button onClick={()=>navigator.clipboard.writeText(JSON.stringify(v,null,2))} onMouseUp={async()=>{try{const card={ name:v.name, description:v.description, attributes:v }; await saveDraft(card);}catch{}}} className="px-3 py-2 rounded border hover:bg-black/5 text-sm">📋 Kopier JSON</button>
              <button onClick={()=>sendDraft(v)} className="px-3 py-2 rounded border hover:bg-black/5 text-sm">🚀 Send (stub)</button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

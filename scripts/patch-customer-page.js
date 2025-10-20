const fs = require('fs');
const p = 'app/admin/customers/[id]/page.tsx';
if(!fs.existsSync(p)){ console.log('ℹ️ Skipped (not found):', p); process.exit(0); }
let s = fs.readFileSync(p,'utf8');
let changed = false;

// import Timeline if missing
if(!/from ['"]@\/src\/components\/ui\/Timeline['"]/.test(s)){
  s = s.replace(/(import .+?\n)(?=import|'use client'|const|type|export|function)/s,
    "$1import Timeline from '@/src/components/ui/Timeline'\n");
  changed = true;
}

// TaskList value fallback
s = s.replace(/<TaskList([^>]*?)value=\{c\.tasks\}/g, '<TaskList$1value={(c.tasks||[])}');
if(/value=\{c\.tasks\}/.test(s)) changed = true;

// Orders map key (include index fallback)
s = s.replace(/\(c\.orders\|\|\[\]\)\.map\(\(o:any\)\)=>\(/, '(c.orders||[]).map((o:any,i:number)=>(');
s = s.replace(/<li key=\{[^}]+\} className="py-2 text-sm flex justify-between">/g,
               '<li key={String(o?.id ?? i)} className="py-2 text-sm flex justify-between">');

if(!changed){ console.log('ℹ️ Customer page looked fine:', p); }
else { fs.writeFileSync(p,s); console.log('✅ Patched:', p); }

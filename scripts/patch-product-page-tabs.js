const fs = require('fs');
const p = 'app/admin/products/[id]/page.tsx';
if(!fs.existsSync(p)){ console.log('ℹ️ Skipped, not found:', p); process.exit(0); }
let s = fs.readFileSync(p,'utf8');
let changed=false;

// import Tabs default + Tab type
if(!/from ['"]@\/src\/components\/ui\/Tabs['"]/.test(s)){
  s = s.replace(/(import .+?;?\n)(?=import|'use client'|const|type|export|function)/s, "$1import Tabs, { type Tab } from '@/src/components/ui/Tabs'\n");
  changed = true;
}

// tabs array: enforce {key,label}
if(/const\s+tabs\s*=\s*\[/.test(s)){
  s = s.replace(/id\s*:/g,'key:');
  s = s.replace(/title\s*:/g,'label:');
  changed = true;
}

// active tab state and handler (if missing)
if(!/const\s*\[\s*tab\s*,\s*setTab\s*\]/.test(s)){
  s = s.replace(/(function\s+ProductDetail\s*\([\s\S]*?\)\s*{)/, "$1\n  const [tab,setTab] = React.useState<string>('overview')");
  changed = true;
}

// ensure Tabs usage correct
s = s.replace(/<Tabs([^>]+)tabs=\{tabs\}([^>]*)>/g, '<Tabs$1 tabs={tabs as Tab[]} active={tab} onChange={setTab} $2>');

// minimal content guards (won't change your JSX, only avoids TS/undefined snafus)
s = s.replace(/(form\.variants)(?!\?\?)/g, '((form?.variants)||[])');

if(changed){ fs.writeFileSync(p,s); console.log('✅ Patched product page tabs:', p); }
else{ console.log('ℹ️ Product page tabs looked fine:', p); }

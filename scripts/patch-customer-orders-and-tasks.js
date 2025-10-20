const fs = require('fs');
const path = 'app/admin/customers/[id]/page.tsx';
if (!fs.existsSync(path)) {
  console.log('ℹ️ Skipped: file not found:', path);
  process.exit(0);
}
let s = fs.readFileSync(path, 'utf8');
let changed = false;

// A) orders map: add index param (i:number)
if (/\(c\.orders\|\|\[\]\)\.map\(\(o:any\)\s*=>\s*\(/.test(s)) {
  s = s.replace(/\(c\.orders\|\|\[\]\)\.map\(\(o:any\)\s*=>\s*\(/, "(c.orders||[]).map((o:any,i:number)=>(");
  changed = true;
}

// B) orders <li> key: use stable fallback {String(o?.id ?? i)}
// (be tolerant: replace any <li key={...} at that spot with ours)
s = s.replace(
  /<li\s+key=\{[^}]+\}\s+className="py-2 text-sm flex justify-between">/g,
  '<li key={String(o?.id ?? i)} className="py-2 text-sm flex justify-between">'
);

// C) TaskList value: ensure fallback []
if (/<TaskList[^>]*value=\{c\.tasks\}/.test(s)) {
  s = s.replace(/<TaskList([^>]*?)value=\{c\.tasks\}/, '<TaskList$1value={c.tasks||[]}');
  changed = true;
} else if (/<TaskList[^>]*value=\{[^}]+\}/.test(s) === false) {
  // If value prop was missing entirely, add it
  s = s.replace(/<TaskList([^>]*)\/>/, '<TaskList$1 value={c.tasks||[]} />');
  s = s.replace(/<TaskList([^>]*)>/, '<TaskList$1 value={c.tasks||[]}>'); // in case of non-selfclosing usage
  changed = true;
}

fs.writeFileSync(path, s);
console.log(changed ? '✅ Patched:' : 'ℹ️ Nothing to change in:', path);

const fs = require('fs'), path = require('path');
const pkgPath = path.join(process.cwd(), 'package.json');
const pkg = JSON.parse(fs.readFileSync(pkgPath,'utf8'));
if(!pkg.scripts) pkg.scripts = {};
for (let i = 2; i < process.argv.length; i+=2) {
  const k = process.argv[i], v = process.argv[i+1];
  if (!k || v===undefined) continue;
  pkg.scripts[k] = v;
}
fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + '\n');
console.log('Updated scripts:', Object.keys(pkg.scripts).sort().join(', '));

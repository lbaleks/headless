const fs = require('fs');
const path = require('path');
const file = path.join(__dirname, 'server.js');
const src = fs.readFileSync(file, 'utf8');

const header = [
  "const path = require('path');",
  "require('dotenv').config({ path: path.resolve(__dirname, '.env') });",
  "// Fallback fra gamle M2_* hvis MAGENTO_* mangler",
  "process.env.MAGENTO_BASE  = process.env.MAGENTO_BASE  || process.env.M2_BASE_URL || '';",
  "let _t = process.env.MAGENTO_TOKEN || process.env.M2_ADMIN_TOKEN || '';",
  "if (_t && !/^Bearer\\s/.test(_t)) _t = 'Bearer ' + _t;",
  "process.env.MAGENTO_TOKEN = _t;",
  ""
].join('\n');

const lines = src.split('\n');

// 1) Finn første «use strict»/kommentar-header startpos
let insertAt = 0;
while (insertAt < lines.length && /^\s*(\/\/|\/\*|\*|['"]use strict['"]|#!)/.test(lines[insertAt])) {
  insertAt++;
}

// 2) Fjern **alle** tidligere dotenv/require/path/MAGENTO-linjer i de første ~60 linjene
const killRe = /(require\(['"]dotenv['"]\)\.config\(|dotenv\/config|^const\s+path\s*=\s*require\(['"]path['"]\)|MAGENTO_BASE|MAGENTO_TOKEN|M2_BASE_URL|M2_ADMIN_TOKEN)/;

  const kept = []
for (const L of lines) {
  if (i < 60 && killRe.test(L)) {
    // dropp
  } else {
    kept.push(L);
  }
  i++;
}

// 3) Sett inn vår kanoniske header etter «insertAt» (juster for linjer droppet)
const before = kept.slice(0, insertAt).join('\n');
const after  = kept.slice(insertAt).join('\n');
const out = [before, header, after].join('\n');

// 4) Skriv tilbake (kun hvis endret)
if (out !== src) {
  fs.writeFileSync(file, out);
  console.log('✅ Ryddet og injisert dotenv-header én gang på toppen av server.js');
} else {
  console.log('ℹ️  Ingen endringer nødvendig (så allerede fin ut).');
}

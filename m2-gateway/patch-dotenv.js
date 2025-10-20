const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, 'server.js');
const src = fs.readFileSync(file, 'utf8');

const inject = [
  "const path = require('path');",
  "require('dotenv').config({ path: path.resolve(__dirname, '.env') });",
  "// Fallback: støtt gamle M2_* hvis MAGENTO_* mangler",
  "process.env.MAGENTO_BASE  = process.env.MAGENTO_BASE  || process.env.M2_BASE_URL || '';",
  "let _t = process.env.MAGENTO_TOKEN || process.env.M2_ADMIN_TOKEN || '';",
  "if (_t && !/^Bearer\\s/.test(_t)) _t = 'Bearer ' + _t;",
  "process.env.MAGENTO_TOKEN = _t;"
].join('\n');

function replaceDotenvCall(code) {
  const re1 = /require\(['"]dotenv['"]\)\.config\(\s*\)/;
  if (re1.test(code)) {
    return code.replace(re1, inject);
  }
  const re2 = /import\s+['"]dotenv\/config['"];?/; // just in case
  if (re2.test(code)) {
    return code.replace(re2, inject);
  }
  // Hvis vi ikke finner noe, injiser etter første linje med requires/`use strict`
  const lines = code.split('\n');
  let insertAt = 0;
  // hopp eventuelle shebang/strict/kommentar-headers
  while (insertAt < lines.length && /^\s*(\/\/|\/\*|\*|['"]use strict['"])/.test(lines[insertAt])) {
    insertAt++;
  }
  lines.splice(insertAt, 0, inject);
  return lines.join('\n');
}

const out = replaceDotenvCall(src);
fs.writeFileSync(file, out);
console.log('✅ Patchet server.js til å lese .env fra m2-gateway og bruke M2_* fallback.');

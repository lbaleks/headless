const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '.env') });

// Fallback fra gamle M2_* hvis MAGENTO_* mangler
process.env.MAGENTO_BASE  = process.env.MAGENTO_BASE  || process.env.M2_BASE_URL || '';
let _t = process.env.MAGENTO_TOKEN || process.env.M2_ADMIN_TOKEN || '';
if (_t && !/^Bearer\s/.test(_t)) _t = 'Bearer ' + _t;
process.env.MAGENTO_TOKEN = _t;

// Krev at begge finnes
if (!process.env.MAGENTO_BASE || !process.env.MAGENTO_TOKEN) {
  console.error('Missing MAGENTO_BASE or MAGENTO_TOKEN in .env');
  process.exit(1);
}

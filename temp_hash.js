const crypto = require('crypto');
const hash = crypto.createHash('sha256').update('9999').digest('hex');
console.log(hash);

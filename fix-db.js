const fs = require('fs');
const filePath = 'backend/src/server.js';
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace("database: 'disabled'", "database: 'firebase'");
fs.writeFileSync(filePath, content, 'utf8');
console.log('Fixed health check database field');

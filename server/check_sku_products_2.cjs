const sqlite3 = require('sqlite3').verbose();
const db = new sqlite3.Database('server/database.db');
db.all("SELECT sku, sku_plain FROM products WHERE sku LIKE '%053M870021%'", (err, rows) => {
    if (err) {
        console.error(err);
    } else {
        console.log(JSON.stringify(rows, null, 2));
    }
    db.close();
});

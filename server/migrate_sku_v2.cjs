const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const dbPath = path.join(__dirname, 'database.db');
const db = new sqlite3.Database(dbPath);

function normalizeSku(sku) {
    if (!sku) return '';
    return sku.toString().replace(/-/g, '').trim().toUpperCase();
}

const tables = ['products', 'erp_stock', 'stock_audit', 'picking_items', 'picking_history'];

db.serialize(async () => {
    console.log('Starting migration v2...');
    for (const table of tables) {
        db.all(`SELECT id, sku, sku_plain FROM ${table}`, (err, rows) => {
            if (err) {
                // If ID doesn't exist, try rowid (for tables without explicit ID)
                db.all(`SELECT rowid as id, sku, sku_plain FROM ${table}`, (err2, rows2) => {
                    if (err2) {
                        console.error(`Error reading ${table}:`, err2.message);
                    } else {
                        migrateRows(table, rows2);
                    }
                });
            } else {
                migrateRows(table, rows);
            }
        });
    }
});

function migrateRows(table, rows) {
    if (!rows || rows.length === 0) {
        console.log(`Table ${table} is empty.`);
        return;
    }
    console.log(`Migrating ${rows.length} rows in ${table}...`);
    let count = 0;
    rows.forEach(row => {
        const correctPlain = normalizeSku(row.sku);
        // We update if it's null, '0', or just different from what it should be
        if (row.sku_plain === null || row.sku_plain === '0' || row.sku_plain !== correctPlain) {
            db.run(`UPDATE ${table} SET sku_plain = ? WHERE ${row.id ? 'id' : 'rowid'} = ?`, [correctPlain, row.id], (err) => {
                if (err) console.error(`Error updating ${table} row ${row.id}:`, err.message);
            });
            count++;
        }
    });
    console.log(`Queued ${count} updates for ${table}.`);
}

// Close DB after a delay to allow async updates to finish (serialise is not enough for nested loops)
setTimeout(() => {
    console.log('Migration finished or timeout reached. Closing DB.');
    db.close();
}, 10000);

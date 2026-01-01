const sqlite3 = require('sqlite3').verbose();
const path = require('path');

const dbPath = path.join(__dirname, 'database.db');
const db = new sqlite3.Database(dbPath);

console.log('🔧 Fixing audit_log table...\n');

db.serialize(() => {
    // Create audit_log table without INDEX in CREATE statement
    db.run(`
        CREATE TABLE IF NOT EXISTS audit_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            table_name TEXT NOT NULL,
            record_id TEXT NOT NULL,
            action TEXT NOT NULL,
            old_value TEXT,
            new_value TEXT,
            user_id TEXT NOT NULL,
            ip_address TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    `, (err) => {
        if (err) {
            console.error('  ❌ Error creating audit_log:', err.message);
        } else {
            console.log('  ✅ audit_log table created');
        }
    });

    // Create indexes separately
    const indexes = [
        'CREATE INDEX IF NOT EXISTS idx_audit_table ON audit_log(table_name)',
        'CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_log(user_id)',
        'CREATE INDEX IF NOT EXISTS idx_audit_time ON audit_log(created_at DESC)',
        'CREATE INDEX IF NOT EXISTS idx_audit_record ON audit_log(record_id)'
    ];

    indexes.forEach(sql => {
        db.run(sql, (err) => {
            if (err) {
                console.error(`  ❌ Error creating index: ${err.message}`);
            }
        });
    });

    console.log('  ✅ Indexes created');
});

setTimeout(() => {
    db.close((err) => {
        if (err) {
            console.error('\n❌ Error closing database:', err.message);
        } else {
            console.log('\n✅ Fix completed successfully!');
            console.log('\n🚀 You can now start the server with: node index.cjs');
        }
        process.exit(0);
    });
}, 2000);

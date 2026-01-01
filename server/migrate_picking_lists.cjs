const sqlite3 = require('sqlite3').verbose();
const path = require('path');

const dbPath = path.join(__dirname, 'database.db');
const db = new sqlite3.Database(dbPath);

console.log('🔄 Migrating picking_lists table to support duplicate order numbers for different customers...');

db.serialize(() => {
    // Step 1: Create new table with correct schema
    db.run(`CREATE TABLE IF NOT EXISTS picking_lists_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        orderNumber TEXT NOT NULL,
        customer TEXT NOT NULL,
        status TEXT,
        createdAt TEXT,
        UNIQUE(orderNumber, customer)
    )`, (err) => {
        if (err) {
            console.error('❌ Error creating new table:', err);
            return;
        }
        console.log('✅ Created new table schema');
    });

    // Step 2: Copy data from old table to new table
    db.run(`INSERT INTO picking_lists_new (id, orderNumber, customer, status, createdAt)
            SELECT id, orderNumber, COALESCE(customer, 'Unknown'), status, createdAt 
            FROM picking_lists`, (err) => {
        if (err) {
            console.error('❌ Error copying data:', err);
            return;
        }
        console.log('✅ Copied existing data');
    });

    // Step 3: Drop old table
    db.run(`DROP TABLE picking_lists`, (err) => {
        if (err) {
            console.error('❌ Error dropping old table:', err);
            return;
        }
        console.log('✅ Dropped old table');
    });

    // Step 4: Rename new table
    db.run(`ALTER TABLE picking_lists_new RENAME TO picking_lists`, (err) => {
        if (err) {
            console.error('❌ Error renaming table:', err);
            return;
        }
        console.log('✅ Renamed new table');
    });

    // Step 5: Recreate indexes
    db.run(`CREATE INDEX IF NOT EXISTS idx_picking_status ON picking_lists(status)`, (err) => {
        if (err) console.error('Error creating status index:', err);
    });

    db.run(`CREATE INDEX IF NOT EXISTS idx_picking_created ON picking_lists(createdAt DESC)`, (err) => {
        if (err) console.error('Error creating created index:', err);
        else console.log('✅ Recreated indexes');
    });

    db.run(`CREATE INDEX IF NOT EXISTS idx_picking_customer ON picking_lists(customer)`, (err) => {
        if (err) console.error('Error creating customer index:', err);
        else console.log('✅ Created customer index');
    });
});

db.close((err) => {
    if (err) {
        console.error('❌ Error closing database:', err);
    } else {
        console.log('✅ Migration completed successfully!');
        console.log('📝 Now you can have the same order number for different customers.');
    }
});

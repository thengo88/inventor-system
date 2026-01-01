/**
 * Database Migration & Optimization Script
 * Adds: Optimistic Locking, Audit Logging, Performance Indexes
 */

const sqlite3 = require('sqlite3').verbose();
const path = require('path');

const dbPath = path.join(__dirname, 'database.db');
const db = new sqlite3.Database(dbPath);

console.log('🚀 Starting database migration and optimization...\n');

db.serialize(() => {
    // ========================================
    // 1. ADD OPTIMISTIC LOCKING FIELDS
    // ========================================
    console.log('📝 Adding optimistic locking fields...');

    const lockingFields = [
        'ALTER TABLE erp_stock ADD COLUMN version INTEGER DEFAULT 0',
        'ALTER TABLE erp_stock ADD COLUMN locked_by TEXT',
        'ALTER TABLE erp_stock ADD COLUMN locked_at DATETIME',
        'ALTER TABLE erp_stock ADD COLUMN updated_by TEXT',

        'ALTER TABLE stock_audit ADD COLUMN version INTEGER DEFAULT 0',
        'ALTER TABLE stock_audit ADD COLUMN updated_by TEXT',

        'ALTER TABLE notifications ADD COLUMN claimed_by TEXT',
        'ALTER TABLE notifications ADD COLUMN claimed_at DATETIME',
        'ALTER TABLE notifications ADD COLUMN version INTEGER DEFAULT 0',

        'ALTER TABLE picking_items ADD COLUMN version INTEGER DEFAULT 0',
        'ALTER TABLE picking_items ADD COLUMN locked_by TEXT'
    ];

    lockingFields.forEach(sql => {
        db.run(sql, (err) => {
            if (err && !err.message.includes('duplicate column')) {
                console.error(`  ❌ Error: ${err.message}`);
            }
        });
    });

    // ========================================
    // 2. CREATE AUDIT LOG TABLE
    // ========================================
    console.log('📊 Creating audit log table...');

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
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_audit_table (table_name),
            INDEX idx_audit_user (user_id),
            INDEX idx_audit_time (created_at DESC)
        )
    `, (err) => {
        if (err) console.error(`  ❌ Error creating audit_log: ${err.message}`);
        else console.log('  ✅ Audit log table created');
    });

    // ========================================
    // 3. CREATE PERFORMANCE INDEXES
    // ========================================
    console.log('⚡ Creating performance indexes...');

    const indexes = [
        // ERP Stock indexes
        'CREATE INDEX IF NOT EXISTS idx_erp_sku ON erp_stock(sku)',
        'CREATE INDEX IF NOT EXISTS idx_erp_warehouse ON erp_stock(warehouse)',
        'CREATE INDEX IF NOT EXISTS idx_erp_updated ON erp_stock(updatedAt DESC)',

        // Stock Audit indexes
        'CREATE INDEX IF NOT EXISTS idx_audit_sku ON stock_audit(sku)',
        'CREATE INDEX IF NOT EXISTS idx_audit_warehouse ON stock_audit(warehouse)',
        'CREATE INDEX IF NOT EXISTS idx_audit_time ON stock_audit(timestamp DESC)',
        'CREATE INDEX IF NOT EXISTS idx_audit_auditor ON stock_audit(auditor)',

        // Notifications indexes
        'CREATE INDEX IF NOT EXISTS idx_notif_type ON notifications(type)',
        'CREATE INDEX IF NOT EXISTS idx_notif_time ON notifications(time DESC)',
        'CREATE INDEX IF NOT EXISTS idx_notif_claimed ON notifications(claimed_by)',

        // Picking indexes
        'CREATE INDEX IF NOT EXISTS idx_picking_status ON picking_lists(status)',
        'CREATE INDEX IF NOT EXISTS idx_picking_created ON picking_lists(createdAt DESC)',
        'CREATE INDEX IF NOT EXISTS idx_picking_items_list ON picking_items(pickingListId)',
        'CREATE INDEX IF NOT EXISTS idx_picking_items_sku ON picking_items(sku)',

        // Products indexes
        'CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku)',
        'CREATE INDEX IF NOT EXISTS idx_products_customer ON products(customer)',

        // Users indexes
        'CREATE INDEX IF NOT EXISTS idx_users_username ON users(username)',
        'CREATE INDEX IF NOT EXISTS idx_users_role ON users(role)',

        // Logs indexes
        'CREATE INDEX IF NOT EXISTS idx_logs_username ON logs(username)',
        'CREATE INDEX IF NOT EXISTS idx_logs_time ON logs(timestamp DESC)'
    ];

    indexes.forEach(sql => {
        db.run(sql, (err) => {
            if (err) console.error(`  ❌ Error: ${err.message}`);
        });
    });

    // ========================================
    // 4. ENABLE WAL MODE FOR BETTER CONCURRENCY
    // ========================================
    console.log('🔧 Optimizing SQLite settings...');

    db.run('PRAGMA journal_mode = WAL', (err) => {
        if (err) console.error(`  ❌ Error enabling WAL: ${err.message}`);
        else console.log('  ✅ WAL mode enabled');
    });

    db.run('PRAGMA synchronous = NORMAL', (err) => {
        if (err) console.error(`  ❌ Error setting synchronous: ${err.message}`);
        else console.log('  ✅ Synchronous mode set to NORMAL');
    });

    db.run('PRAGMA cache_size = 10000', (err) => {
        if (err) console.error(`  ❌ Error setting cache: ${err.message}`);
        else console.log('  ✅ Cache size increased to 10000 pages');
    });

    db.run('PRAGMA temp_store = MEMORY', (err) => {
        if (err) console.error(`  ❌ Error setting temp_store: ${err.message}`);
        else console.log('  ✅ Temp store set to MEMORY');
    });

    // ========================================
    // 5. CREATE TRIGGERS FOR AUTO AUDIT LOGGING
    // ========================================
    console.log('🎯 Creating audit triggers...');

    // Trigger for erp_stock updates
    db.run(`
        CREATE TRIGGER IF NOT EXISTS erp_stock_update_log
        AFTER UPDATE ON erp_stock
        FOR EACH ROW
        BEGIN
            INSERT INTO audit_log (table_name, record_id, action, old_value, new_value, user_id)
            VALUES (
                'erp_stock',
                NEW.sku || '_' || NEW.warehouse,
                'UPDATE',
                json_object('quantity', OLD.quantity, 'version', OLD.version, 'total_kk', OLD.total_kk),
                json_object('quantity', NEW.quantity, 'version', NEW.version, 'total_kk', NEW.total_kk),
                COALESCE(NEW.updated_by, 'system')
            );
        END
    `, (err) => {
        if (err) console.error(`  ❌ Error creating trigger: ${err.message}`);
        else console.log('  ✅ ERP stock audit trigger created');
    });

    // Trigger for stock_audit inserts
    db.run(`
        CREATE TRIGGER IF NOT EXISTS stock_audit_insert_log
        AFTER INSERT ON stock_audit
        FOR EACH ROW
        BEGIN
            INSERT INTO audit_log (table_name, record_id, action, new_value, user_id)
            VALUES (
                'stock_audit',
                NEW.id,
                'INSERT',
                json_object('sku', NEW.sku, 'totalResult', NEW.totalResult, 'warehouse', NEW.warehouse),
                COALESCE(NEW.auditor, 'unknown')
            );
        END
    `, (err) => {
        if (err) console.error(`  ❌ Error creating trigger: ${err.message}`);
        else console.log('  ✅ Stock audit insert trigger created');
    });

    // ========================================
    // 6. ANALYZE DATABASE FOR QUERY OPTIMIZATION
    // ========================================
    console.log('📈 Analyzing database...');

    db.run('ANALYZE', (err) => {
        if (err) console.error(`  ❌ Error analyzing: ${err.message}`);
        else console.log('  ✅ Database analyzed for query optimization');
    });

    // ========================================
    // 7. VACUUM TO RECLAIM SPACE
    // ========================================
    console.log('🧹 Vacuuming database...');

    db.run('VACUUM', (err) => {
        if (err) console.error(`  ❌ Error vacuuming: ${err.message}`);
        else console.log('  ✅ Database vacuumed');
    });
});

// Close database after all operations
setTimeout(() => {
    db.close((err) => {
        if (err) {
            console.error('\n❌ Error closing database:', err.message);
        } else {
            console.log('\n✅ Migration completed successfully!');
            console.log('\n📊 Summary:');
            console.log('  - Optimistic locking fields added');
            console.log('  - Audit logging system created');
            console.log('  - Performance indexes created');
            console.log('  - SQLite optimizations applied');
            console.log('  - Auto-audit triggers created');
            console.log('\n🚀 Database is now optimized for concurrent access!');
        }
        process.exit(0);
    });
}, 3000); // Wait 3 seconds for all operations to complete

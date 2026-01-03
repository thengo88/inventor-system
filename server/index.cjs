


const express = require('express');
const sqlite3 = require('sqlite3').verbose();
const cors = require('cors');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const bodyParser = require('body-parser');

// Import database helpers for optimistic locking & transactions
const {
    withTransaction,
    updateErpStock,
    updateStockAudit,
    claimNotification,
    retryWithBackoff,
    logAudit
} = require('./db_helper.cjs');


const app = express();
const http = require('http');
const https = require('https');

// SSL Configuration
let sslOptions = null;
try {
    const keyPath = path.join(__dirname, 'key.pem');
    const certPath = path.join(__dirname, 'cert.pem');
    if (fs.existsSync(keyPath) && fs.existsSync(certPath)) {
        sslOptions = {
            key: fs.readFileSync(keyPath),
            cert: fs.readFileSync(certPath)
        };
        console.log('✅ SSL Certificates found. Enabling HTTPS...');
    }
} catch (err) {
    console.error('❌ Error loading SSL certificates:', err);
}

const httpPort = process.env.PORT || 3000;
const httpsPort = 3443; // Separate port for HTTPS (local only)

// Create server instances
const httpSrv = http.createServer(app);
const httpsSrv = sslOptions ? https.createServer(sslOptions, app) : null;

// Bind Socket.IO to BOTH servers if HTTPS is available
// Note: socket.io accepts a server instance or port. For multiple servers, 
// we typically attach to one and handle CORS for both origins.
// Or we create two io instances. Simplifying here: attach to HTTP primarily for now 
// or attach to both. Let's start both servers.

httpSrv.listen(httpPort, '0.0.0.0', () => {
    console.log(`🚀 HTTP Server running on: http://0.0.0.0:${httpPort}`);
});

let ioServer = httpSrv; // Default IO binding

if (sslOptions && httpsSrv) {
    httpsSrv.listen(httpsPort, '0.0.0.0', () => {
        console.log(`🔒 HTTPS Server running on: https://0.0.0.0:${httpsPort}`);
    });
    // If HTTPS is available, we want IO to work there too.
    // Socket.io standard way to attach to multiple servers is limited in simple init.
    // We will attach IO to the HTTPS server as well if present.
    ioServer = httpsSrv;
} else {
    console.log('⚠️ Security Mode: HTTP Only (No SSL certificates found for HTTPS)');
}

// Bind Socket.IO
// Ideally we need it on both. 
// A robust way: const io = require('socket.io')(); io.attach(httpSrv); io.attach(httpsSrv);
const io = require('socket.io')({
    cors: { origin: "*" }
});
io.attach(httpSrv);
if (httpsSrv) io.attach(httpsSrv);

/* 
// Previous single server logic removed
let serverToUse = httpSrv;
if (sslOptions && httpsSrv) { serverToUse = httpsSrv; ... }
*/

// Middleware
app.use(cors());
// app.use(bodyParser.json()); // Deprecated/Old
app.use(express.json()); // Modern
app.use(express.urlencoded({ extended: true }));

// Global Data Sync Middleware
// Emits 'system_data_change' on any successful modification request
app.use((req, res, next) => {
    // Only care about modification methods
    if (['POST', 'PUT', 'DELETE', 'PATCH'].includes(req.method)) {
        res.on('finish', () => {
            if (res.statusCode >= 200 && res.statusCode < 300) {
                // Determine broad category based on path to help frontend optimize (optional)
                const category = req.path.split('/')[2] || 'general';
                io.emit('system_data_change', {
                    method: req.method,
                    path: req.path,
                    category: category,
                    timestamp: Date.now()
                });
                console.log(`[Socket] Emitted system_data_change for ${req.method} ${req.path}`);
            }
        });
    }
    next();
});

// 🚨 EMERGENCY LOGIN ROUTE (GET) - Bypasses body parsing issues
app.get('/api/login-emergency', (req, res) => {
    const { username, password } = req.query; // Use Query Params
    console.log(`[EMERGENCY LOGIN] User: ${username}`);

    if (username && username.toLowerCase() === 'admin' && password === 'admin123') {
        return res.json({
            id: 1,
            username: 'admin',
            role: 'admin',
            assignedRecs: null,
            assignedTyps: null,
            assignedPs: null,
            assignedOprs: null
        });
    }
    res.status(401).json({ error: 'Auth failed' });
});

// SKU Normalization Helper
function normalizeSku(sku) {
    if (!sku) return '';
    return sku.toString().replace(/-/g, '').trim().toUpperCase();
}


// Multer Setup
const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        const uploadDir = path.join(__dirname, 'uploads');
        if (!require('fs').existsSync(uploadDir)) {
            require('fs').mkdirSync(uploadDir);
        }
        cb(null, uploadDir);
    },
    filename: (req, file, cb) => {
        cb(null, Date.now() + path.extname(file.originalname));
    }
});
const upload = multer({ storage });

app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// Serve static files from both potential public folders
app.use(express.static(path.join(__dirname, 'public_flutter')));
app.use(express.static(path.join(__dirname, 'public')));

// Explicit route for root to ensure it serves index.html
app.get('/', (req, res) => {
    const flutterIndex = path.join(__dirname, 'public_flutter', 'index.html');
    const publicIndex = path.join(__dirname, 'public', 'index.html');

    if (fs.existsSync(flutterIndex)) {
        res.sendFile(flutterIndex);
    } else if (fs.existsSync(publicIndex)) {
        res.sendFile(publicIndex);
    } else {
        res.status(404).send('Index file not found in public_flutter or public. Please check your deployment build artifacts.');
    }
});




// DB Setup
let db;
if (process.env.TURSO_DATABASE_URL) {
    console.log('🌐 TURSO MODE: Using managed database');
    db = require('./db_turso.cjs');
} else {
    const dbPath = path.join(__dirname, 'database.db');
    db = new sqlite3.Database(dbPath, (err) => {
        if (err) console.error(err.message);
        else {
            db.run("PRAGMA busy_timeout = 30000"); // Increase wait time to 30s to prevent I/O blockers
            console.log(`Connected to database at: ${dbPath}`);
        }
    });
}

// --- Warehouse Layout Config ---
const CONFIG_FILE = path.join(__dirname, 'warehouse_config.json');

app.get('/api/warehouse-config', (req, res) => {
    if (fs.existsSync(CONFIG_FILE)) {
        res.json(JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8')));
    } else {
        res.json(null); // No config saved yet
    }
});

app.post('/api/warehouse-config', (req, res) => {
    try {
        fs.writeFileSync(CONFIG_FILE, JSON.stringify(req.body, null, 2));
        // Emit specific event for layout notification
        io.emit('system_data_change', {
            method: 'POST',
            path: '/api/warehouse-config',
            category: 'config',
            timestamp: Date.now()
        });
        res.json({ success: true });
    } catch (e) {
        console.error('Save config error:', e);
        res.status(500).json({ error: e.message });
    }
});

// Create tables
db.serialize(() => {
    db.run(`CREATE TABLE IF NOT EXISTS products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sku TEXT UNIQUE,
        sku_plain TEXT,
        name TEXT,
        packagingStandard TEXT,
        imageUrl TEXT,
        layoutPosition TEXT,
        customer TEXT,
        description TEXT,
        imageUrl2 TEXT
    )`);
    db.run(`ALTER TABLE products ADD COLUMN sku_plain TEXT`, (err) => { });


    db.run(`CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE,
        password TEXT,
        role TEXT,
        assignedRecs TEXT,
        assignedTyps TEXT,
        assignedPs TEXT,
        assignedOprs TEXT,
        assignedTr TEXT,
        assignedGate TEXT,
        assignedLine TEXT,
        assignedZone TEXT,
        assignedBox TEXT
    )`);

    // Migration for existing users table
    db.run(`ALTER TABLE users ADD COLUMN assignedRecs TEXT`, (err) => { });
    db.run(`ALTER TABLE users ADD COLUMN assignedTyps TEXT`, (err) => { });
    db.run(`ALTER TABLE users ADD COLUMN assignedPs TEXT`, (err) => { });
    db.run(`ALTER TABLE users ADD COLUMN assignedOprs TEXT`, (err) => { });
    db.run(`ALTER TABLE users ADD COLUMN assignedTr TEXT`, (err) => { });
    db.run(`ALTER TABLE users ADD COLUMN assignedGate TEXT`, (err) => { });
    db.run(`ALTER TABLE users ADD COLUMN assignedLine TEXT`, (err) => { });
    db.run(`ALTER TABLE users ADD COLUMN assignedZone TEXT`, (err) => { });
    db.run(`ALTER TABLE users ADD COLUMN assignedBox TEXT`, (err) => { });

    db.run(`CREATE TABLE IF NOT EXISTS logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT,
        action TEXT,
        details TEXT,
        timestamp TEXT
    )`);

    db.run(`CREATE TABLE IF NOT EXISTS picking_lists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        orderNumber TEXT NOT NULL,
        customer TEXT NOT NULL,
        status TEXT,
        createdAt TEXT,
        UNIQUE(orderNumber, customer)
    )`);

    db.run(`CREATE TABLE IF NOT EXISTS erp_stock (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sku TEXT,
        sku_plain TEXT,
        name TEXT,
        warehouse TEXT,
        quantity TEXT,
        kk1 TEXT DEFAULT '0',
        kk2 TEXT DEFAULT '0',
        kk3 TEXT DEFAULT '0',
        kk4 TEXT DEFAULT '0',
        kk5 TEXT DEFAULT '0',
        kk6 TEXT DEFAULT '0',
        kk7 TEXT DEFAULT '0',
        kk8 TEXT DEFAULT '0',
        kk9 TEXT DEFAULT '0',
        kk10 TEXT DEFAULT '0',
        total_kk TEXT DEFAULT '0',
        difference TEXT DEFAULT '0',
        diff_nn TEXT DEFAULT '0',
        packing_diff TEXT DEFAULT '0',
        replenish TEXT DEFAULT '0',
        updatedAt TEXT,
        version INTEGER DEFAULT 0
    )`);

    // Migrations for erp_stock
    const erpCols = ['kk1', 'kk2', 'kk3', 'kk4', 'kk5', 'kk6', 'kk7', 'kk8', 'kk9', 'kk10', 'total_kk', 'difference', 'diff_nn', 'packing_diff', 'replenish', 'merged_skus'];
    erpCols.forEach(col => {
        db.run(`ALTER TABLE erp_stock ADD COLUMN ${col} TEXT DEFAULT '0'`, (err) => { });
    });
    db.run(`ALTER TABLE erp_stock ADD COLUMN sku_plain TEXT`, (err) => { });

    db.run(`ALTER TABLE erp_stock ADD COLUMN custom_data TEXT DEFAULT '{}'`, (err) => { });
    db.run(`ALTER TABLE erp_stock ADD COLUMN version INTEGER DEFAULT 0`, (err) => { });
    db.run(`CREATE UNIQUE INDEX IF NOT EXISTS idx_erp_stock_sku_wh ON erp_stock (sku, warehouse)`);
    db.run(`CREATE INDEX IF NOT EXISTS idx_erp_stock_sku_plain ON erp_stock (sku_plain)`);

    // Ensure merged_skus is initialized as empty array string if not 0
    db.run(`UPDATE erp_stock SET merged_skus = '[]' WHERE merged_skus = '0' OR merged_skus IS NULL`);

    db.run(`CREATE TABLE IF NOT EXISTS stock_audit (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sku TEXT,
        sku_plain TEXT,
        warehouse TEXT,
        packagingStandard INTEGER,
        horRows INTEGER,
        verRows INTEGER,
        evenRows INTEGER,
        oddRows INTEGER,
        individualBags INTEGER,
        totalResult INTEGER,
        auditor TEXT,
        timestamp TEXT,
        note TEXT
    )`);

    db.run(`ALTER TABLE stock_audit ADD COLUMN warehouse TEXT`, (err) => { });
    db.run(`ALTER TABLE stock_audit ADD COLUMN sku_plain TEXT`, (err) => { });
    db.run(`ALTER TABLE stock_audit ADD COLUMN note TEXT`, (err) => { });
    db.run(`ALTER TABLE stock_audit ADD COLUMN location TEXT`, (err) => { });
    db.run(`ALTER TABLE stock_audit ADD COLUMN version INTEGER DEFAULT 0`, (err) => { });


    db.run(`CREATE TABLE IF NOT EXISTS picking_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pickingListId INTEGER,
        sku TEXT,
        sku_plain TEXT,
        productName TEXT,
        quantityRequired INTEGER,
        quantityPicked INTEGER DEFAULT 0,
        gate TEXT,
        line TEXT,
        zone TEXT,
        rec_hh TEXT,
        tr_no TEXT,
        odr_typ TEXT,
        box TEXT,
        ps_cd TEXT,
        rec_opr TEXT,
        assigned_user TEXT,
        FOREIGN KEY(pickingListId) REFERENCES picking_lists(id)
    )`);
    db.run(`ALTER TABLE picking_items ADD COLUMN sku_plain TEXT`, (err) => { });


    db.run(`CREATE TABLE IF NOT EXISTS picking_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT,
        orderNumber TEXT,
        sku TEXT,
        sku_plain TEXT,
        productName TEXT,
        quantityPicked INTEGER,
        rec_hh TEXT,
        odr_typ TEXT,
        ps_cd TEXT,
        rec_opr TEXT,
        zone TEXT,
        tr_no TEXT,
        gate TEXT,
        line TEXT,
        box TEXT,
        timestamp TEXT
    )`);

    // Migration for existing tables
    db.run(`ALTER TABLE picking_history ADD COLUMN sku_plain TEXT`, (err) => { });
    db.run(`ALTER TABLE picking_history ADD COLUMN zone TEXT`, (err) => { });

    db.run(`ALTER TABLE picking_history ADD COLUMN tr_no TEXT`, (err) => { });
    db.run(`ALTER TABLE picking_history ADD COLUMN gate TEXT`, (err) => { });
    db.run(`ALTER TABLE picking_history ADD COLUMN line TEXT`, (err) => { });
    db.run(`ALTER TABLE picking_history ADD COLUMN box TEXT`, (err) => { });

    // Migration for existing tables
    db.run(`ALTER TABLE picking_items ADD COLUMN gate TEXT`, (err) => { });
    db.run(`ALTER TABLE picking_items ADD COLUMN line TEXT`, (err) => { });
    db.run(`ALTER TABLE picking_items ADD COLUMN zone TEXT`, (err) => { });
    db.run(`ALTER TABLE picking_items ADD COLUMN rec_hh TEXT`, (err) => { });
    db.run(`ALTER TABLE picking_items ADD COLUMN tr_no TEXT`, (err) => { });
    db.run(`ALTER TABLE picking_items ADD COLUMN odr_typ TEXT`, (err) => { });
    db.run(`ALTER TABLE picking_items ADD COLUMN box TEXT`, (err) => { });
    db.run(`ALTER TABLE picking_items ADD COLUMN ps_cd TEXT`, (err) => { });
    db.run(`ALTER TABLE picking_items ADD COLUMN rec_opr TEXT`, (err) => { });
    db.run(`ALTER TABLE picking_items ADD COLUMN imageUrl TEXT`, (err) => { });
    db.run(`ALTER TABLE picking_items ADD COLUMN packagingStandard TEXT`, (err) => { });
    db.run(`ALTER TABLE picking_items ADD COLUMN assigned_user TEXT`, (err) => { });


    db.run(`ALTER TABLE products ADD COLUMN description TEXT`, (err) => { });
    db.run(`ALTER TABLE products ADD COLUMN imageUrl2 TEXT`, (err) => { });
    db.run(`ALTER TABLE products ADD COLUMN stock REAL DEFAULT 0.0`, (err) => { });

    // Initial admin
    const hashedAdmin = crypto.createHash('sha256').update('123456').digest('hex');
    db.run(`INSERT OR IGNORE INTO users (username, password, role) VALUES ('admin', '${hashedAdmin}', 'admin')`, [], () => {
        // Ensure admin password is always 123456 (Force Reset for testing)
        db.run(`UPDATE users SET password = ? WHERE username = 'admin'`, [hashedAdmin]);
        console.log('✅ Admin account ensured: admin / 123456');
    });

    db.run(`CREATE TABLE IF NOT EXISTS notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT,
        message TEXT,
        time TEXT,
        readBy TEXT DEFAULT '[]',
        metadata TEXT DEFAULT '{}',
        hiddenBy TEXT DEFAULT '[]'
    )`);

    db.run(`ALTER TABLE notifications ADD COLUMN hiddenBy TEXT DEFAULT '[]'`, (err) => { });
    db.run(`ALTER TABLE notifications ADD COLUMN claimed_by TEXT`, (err) => { });
    db.run(`ALTER TABLE notifications ADD COLUMN claimed_at TEXT`, (err) => { });

    db.run(`CREATE TABLE IF NOT EXISTS system_settings (
        key TEXT PRIMARY KEY,
        value TEXT
    )`);
    db.run(`INSERT OR IGNORE INTO system_settings (key, value) VALUES ('stockSource', 'anc-wms')`);
    db.run(`UPDATE system_settings SET value = 'anc-wms' WHERE value = 'anc-vms'`);
});

const xlsx = require('xlsx');
let puppeteer;
try {
    puppeteer = require('puppeteer');
} catch (e) {
    console.warn('Puppeteer not installed, ERP scraping will not work');
}


// Implementation of Picking Routes
// Helper to get where clause for picking filters
async function getPickingFilters(user, customFilters = {}) {
    let filters = [];
    let params = [];

    const addFilter = (col, val) => {
        if (val && val.trim()) {
            const list = val.split(',').map(s => s.trim().toUpperCase());
            filters.push(`TRIM(UPPER(${col})) IN (${list.map(() => '?').join(',')})`);
            params.push(...list);
            return true;
        }
        return false;
    };

    if (user && user.role !== 'admin') {
        // Enforce trip-specific assignment
        // A user only sees items specifically assigned to them in the picking_items table
        filters.push(`TRIM(UPPER(pi.assigned_user)) = ?`);
        params.push(user.username.trim().toUpperCase());
    } else {
        // Admin or No User - use custom filters if provided
        addFilter('pi.rec_hh', customFilters.recs);
        addFilter('pi.tr_no', customFilters.tr);
        addFilter('pi.odr_typ', customFilters.typs);
        addFilter('pi.ps_cd', customFilters.ps);
        addFilter('pi.gate', customFilters.gate);
        addFilter('pi.line', customFilters.line);
        addFilter('pi.zone', customFilters.zone);
        addFilter('pi.box', customFilters.box);

        if (customFilters.oprs && customFilters.oprs.trim()) {
            const oprList = customFilters.oprs.split(',').map(s => s.trim().toUpperCase());
            const oprFilters = oprList.map(() => `TRIM(UPPER(pi.rec_opr)) LIKE ?`).join(' OR ');
            filters.push(`(${oprFilters})`);
            params.push(...oprList.map(o => o + '%'));
        }
    }


    return { filters, params };
}

app.get('/api/picking', (req, res) => {
    const { username, recs, typs, ps, oprs, tr, gate, line, zone, box, isFiltered } = req.query;
    console.log(`[GET /api/picking] User: ${username}, isFiltered: ${isFiltered}`);

    const proceed = async (user) => {
        let { filters, params } = await getPickingFilters(user, { recs, typs, ps, oprs, tr, gate, line, zone, box });

        let whereClause = '';
        if (filters.length > 0) {
            whereClause = 'WHERE ' + filters.join(' AND ');
        } else if (user && user.role !== 'admin') {
            // User with NO assignments see nothing
            return res.json([]);
        }

        const query = `
            SELECT 
                pl.*, 
                COUNT(pi.id) as totalItems,
                SUM(pi.quantityRequired) as totalQtyRequired,
                SUM(pi.quantityPicked) as totalQtyPicked
            FROM picking_lists pl
            JOIN picking_items pi ON pl.id = pi.pickingListId
            ${whereClause}
            GROUP BY pl.id
            HAVING totalItems > 0
            ORDER BY pl.createdAt DESC
        `;

        db.all(query, params, (err, rows) => {
            if (err) return res.status(500).json({ error: err.message });
            res.json(rows);
        });
    };

    if (username) {
        db.get(`SELECT * FROM users WHERE username = ?`, [username], (err, user) => {
            if (err) return res.status(500).json({ error: err.message });
            proceed(user);
        });
    } else {
        proceed(null);
    }
});

app.get('/api/picking/unique-values', (req, res) => {
    console.log('[GET /api/picking/unique-values] Request started');
    const queries = {
        recs: 'SELECT DISTINCT TRIM(rec_hh) as value FROM picking_items WHERE rec_hh IS NOT NULL AND rec_hh != "" ORDER BY value',
        typs: 'SELECT DISTINCT TRIM(odr_typ) as value FROM picking_items WHERE odr_typ IS NOT NULL AND odr_typ != "" ORDER BY value',
        ps: 'SELECT DISTINCT TRIM(ps_cd) as value FROM picking_items WHERE ps_cd IS NOT NULL AND ps_cd != "" ORDER BY value',
        oprs: 'SELECT DISTINCT TRIM(rec_opr) as value FROM picking_items WHERE rec_opr IS NOT NULL AND rec_opr != "" ORDER BY value',
        tr: 'SELECT DISTINCT TRIM(tr_no) as value FROM picking_items WHERE tr_no IS NOT NULL AND tr_no != "" ORDER BY value',
        gate: 'SELECT DISTINCT TRIM(gate) as value FROM picking_items WHERE gate IS NOT NULL AND gate != "" ORDER BY value',
        line: 'SELECT DISTINCT TRIM(line) as value FROM picking_items WHERE line IS NOT NULL AND line != "" ORDER BY value',
        zone: 'SELECT DISTINCT TRIM(zone) as value FROM picking_items WHERE zone IS NOT NULL AND zone != "" ORDER BY value',
        box: 'SELECT DISTINCT TRIM(box) as value FROM picking_items WHERE box IS NOT NULL AND box != "" ORDER BY value'
    };

    const results = {};
    const keys = Object.keys(queries);
    let completed = 0;
    let hasError = false;

    keys.forEach(key => {
        db.all(queries[key], [], (err, rows) => {
            if (err) {
                console.error(`[GET /api/picking/unique-values] Query error for ${key}:`, err.message);
                if (!hasError) {
                    hasError = true;
                    return res.status(500).json({ error: err.message });
                }
                return;
            }
            results[key] = rows.map(r => r.value);
            completed++;
            if (completed === keys.length && !hasError) {
                console.log('[GET /api/picking/unique-values] Success. Found counts:',
                    Object.keys(results).map(k => `${k}: ${results[k].length}`).join(', '));
                res.json(results);
            }
        });
    });
});

// History Routes (Defined BEFORE :id to avoid conflict)
app.post('/api/picking/history', (req, res) => {
    const { username, orderNumber, sku, productName, quantityPicked, rec_hh, odr_typ, ps_cd, rec_opr, zone, tr_no, gate, line, box, timestamp } = req.body;
    const query = `INSERT INTO picking_history (username, orderNumber, sku, productName, quantityPicked, rec_hh, odr_typ, ps_cd, rec_opr, zone, tr_no, gate, line, box, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;
    db.run(query, [username, orderNumber, sku, productName, quantityPicked, rec_hh, odr_typ, ps_cd, rec_opr, zone, tr_no, gate, line, box, timestamp], function (err) {
        if (err) return res.status(500).json({ error: err.message });
        res.json({ id: this.lastID });
    });
});

app.get('/api/picking/history', (req, res) => {
    db.all(`SELECT * FROM picking_history ORDER BY timestamp DESC`, [], (err, rows) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json(rows);
    });
});

app.delete('/api/picking/history/clear', (req, res) => {
    db.run(`DELETE FROM picking_history`, [], (err) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json({ message: 'History cleared' });
    });
});

app.get('/api/picking/:id', (req, res) => {
    const { username, recs, typs, ps, oprs, tr, gate, line, zone, box } = req.query;
    console.log(`[GET /api/picking/${req.params.id}] User: ${username}`);

    db.get(`SELECT * FROM picking_lists WHERE id = ?`, [req.params.id], async (err, order) => {
        if (err) return res.status(500).json({ error: err.message });
        if (!order) return res.status(404).json({ error: 'Order not found' });

        const proceed = async (user) => {
            let { filters, params } = await getPickingFilters(user, { recs, typs, ps, oprs, tr, gate, line, zone, box });

            let whereClause = 'WHERE pickingListId = ?';
            let queryParams = [order.id, ...params];

            if (filters.length > 0) {
                // Adjust pi. prefix if filters were built for the main list JOIN
                let adjustedFilters = filters.map(f => f.replace('pi.', ''));
                whereClause += ' AND ' + adjustedFilters.join(' AND ');
            } else if (user && user.role !== 'admin') {
                order.items = [];
                return res.json(order);
            }

            db.all(`SELECT * FROM picking_items ${whereClause}`, queryParams, (err, items) => {
                if (err) return res.status(500).json({ error: err.message });
                order.items = items;
                res.json(order);
            });
        };

        if (username) {
            db.get(`SELECT * FROM users WHERE username = ?`, [username], (err, user) => {
                if (err) return res.status(500).json({ error: err.message });
                proceed(user);
            });
        } else {
            proceed(null);
        }
    });
});


app.get('/api/me/:username', (req, res) => {
    db.get(`SELECT id, username, role, assignedRecs, assignedTyps, assignedPs, assignedOprs, assignedTr, assignedGate, assignedLine, assignedZone, assignedBox FROM users WHERE username = ?`, [req.params.username], (err, row) => {
        if (err) return res.status(500).json({ error: err.message });
        if (row) {
            res.json(row);
        } else {
            res.status(404).json({ error: 'User not found' });
        }
    });
});

app.post('/api/picking', (req, res) => {
    const { orderNumber, customer, items } = req.body;
    db.run(`INSERT INTO picking_lists (orderNumber, customer, status, createdAt) VALUES (?, ?, 'pending', ?)`,
        [orderNumber, customer, new Date().toISOString()],
        async function (err) {
            if (err) return res.status(500).json({ error: err.message });
            const listId = this.lastID;
            const stmt = db.prepare(`INSERT INTO picking_items (pickingListId, sku, productName, quantityRequired) VALUES (?, ?, ?, ?)`);

            const promises = items.map(item => {
                return new Promise((resolve, reject) => {
                    stmt.run(listId, item.sku, item.productName || item.name, item.quantityRequired || item.quantity, (err) => {
                        if (err) reject(err); else resolve();
                    });
                });
            });

            try {
                await Promise.all(promises);
                stmt.finalize();
                res.json({ id: listId });
            } catch (insErr) {
                stmt.finalize();
                res.status(500).json({ error: insErr.message });
            }
        }
    );
});


// Get all headers from Excel sheet for mapping
app.post('/api/picking/headers', upload.single('file'), (req, res) => {
    const { selectedSheet } = req.body;
    if (!req.file) return res.status(400).json({ error: 'No file uploaded' });

    try {
        const workbook = xlsx.readFile(req.file.path);
        const sheetName = selectedSheet || workbook.SheetNames[0];
        const sheet = workbook.Sheets[sheetName];
        if (!sheet) throw new Error(`Sheet "${sheetName}" not found`);

        const rawData = xlsx.utils.sheet_to_json(sheet, { header: 1 });

        // User explicitly requested Row 1 (first row) as header
        let bestRow = rawData.length > 0 ? rawData[0] : null;

        const headers = [];
        if (bestRow) {
            bestRow.forEach(cell => {
                const val = (cell !== null && cell !== undefined) ? cell.toString().trim() : "";
                // Include all columns if they have content, or even if empty if position matters?
                // User said "show all columns in the first row".
                // We'll push empty string if empty, or filter?
                // Usually dropdowns ignore empty strings or look bad. 
                // Let's keep existing logic: push if val is truthy. 
                // BUT if user wants "all columns", maybe they mean index-based? 
                // Unlikely for dropdown mapping. Let's stick to valid values.
                if (val) headers.push(val);
            });
        }



        res.json({ headers });

        setTimeout(() => {
            try { if (fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path); } catch (e) { }
        }, 1000);
    } catch (err) {
        if (req.file && fs.existsSync(req.file.path)) {
            try { fs.unlinkSync(req.file.path); } catch (e) { }
        }
        res.status(500).json({ error: 'Failed to read headers: ' + err.message });
    }
});

// Get sheet names from Excel file
app.post('/api/picking/sheets', upload.single('file'), (req, res) => {
    console.log('[POST /api/picking/sheets] Request received');
    if (!req.file) {
        console.log('[POST /api/picking/sheets] No file uploaded');
        return res.status(400).json({ error: 'No file uploaded' });
    }

    console.log('[POST /api/picking/sheets] File path:', req.file.path);
    try {
        const workbook = xlsx.readFile(req.file.path);
        const sheetNames = workbook.SheetNames;
        console.log('[POST /api/picking/sheets] Sheet names found:', sheetNames);

        // Send response first so user isn't blocked by deletion
        res.json({ sheets: sheetNames });

        // Try clean up in the background
        setTimeout(() => {
            try {
                if (fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path);
            } catch (e) {
                console.warn('[POST /api/picking/sheets] Background cleanup failed (likely busy):', e.message);
            }
        }, 1000);

    } catch (err) {
        console.error('[POST /api/picking/sheets] Error reading Excel sheets:', err);
        if (req.file && fs.existsSync(req.file.path)) {
            try { fs.unlinkSync(req.file.path); } catch (e) { }
        }
        if (!res.headersSent) {
            res.status(500).json({ error: 'Failed to read Excel file: ' + err.message });
        }
    }
});


// Get available dates from Excel sheet
app.post('/api/picking/dates', upload.single('file'), (req, res) => {
    const { selectedSheet } = req.body;
    if (!req.file) return res.status(400).json({ error: 'No file uploaded' });

    try {
        const workbook = xlsx.readFile(req.file.path);
        const sheetName = selectedSheet || workbook.SheetNames[0];
        const sheet = workbook.Sheets[sheetName];
        if (!sheet) throw new Error(`Sheet "${sheetName}" not found`);

        const rawData = xlsx.utils.sheet_to_json(sheet, { header: 1 });

        const norm = (str) => {
            if (!str) return '';
            return str.toString()
                .toLowerCase()
                .normalize("NFD")
                .replace(/[\u0300-\u036f]/g, "")
                .replace(/đ/g, "d")
                .replace(/[^a-z0-9]/g, "");
        };

        const headerSet = new Set();
        let bestRow = null;
        let maxMatches = -1;
        const allKeywords = Object.values(keywordConfig).flat();

        rawData.forEach((row, index) => {
            if (!row || !Array.isArray(row) || row.length === 0) return;

            let matchCount = 0;
            row.forEach(cell => {
                if (cell) {
                    const s = norm(cell);
                    if (allKeywords.includes(s)) matchCount++;
                }
            });

            if (matchCount > maxMatches) {
                maxMatches = matchCount;
                bestRow = row;
            }
        });

        // Nếu không có từ khóa nào khớp, lấy dòng đầu tiên có dữ liệu làm fallback
        if (!bestRow || maxMatches === 0) {
            bestRow = rawData.find(r => r && r.length > 0 && r.some(c => c !== null && c !== ""));
        }

        if (bestRow) {
            bestRow.forEach(cell => {
                if (cell !== null && cell !== undefined && cell.toString().trim() !== "") {
                    headerSet.add(cell.toString().trim());
                }
            });
        }

        const headers = Array.from(headerSet);
        console.log(`[POST /api/picking/dates] Found ${headers.length} potential date/data headers (Max matches: ${maxMatches})`);
        res.json({ dates: headers });

        setTimeout(() => {
            try { if (fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path); } catch (e) { }
        }, 1000);
    } catch (err) {
        if (req.file && fs.existsSync(req.file.path)) {
            try { fs.unlinkSync(req.file.path); } catch (e) { }
        }
        res.status(500).json({ error: 'Failed to read dates: ' + err.message });
    }
});


app.post('/api/picking/import', upload.single('file'), (req, res) => {
    if (!req.file) return res.status(400).json({ error: 'No file uploaded' });

    let { orderNumber: baseOrderNumber, customer, selectedSheet, selectedDate } = req.body;
    const workbook = xlsx.readFile(req.file.path);
    const sheetName = selectedSheet || workbook.SheetNames[0];

    if (!workbook.SheetNames.includes(sheetName)) {
        try { fs.unlinkSync(req.file.path); } catch (e) { }
        return res.status(400).json({ error: `Sheet "${sheetName}" not found in Excel file` });
    }

    const sheet = workbook.Sheets[sheetName];
    const rawData = xlsx.utils.sheet_to_json(sheet, { header: 1 });

    const norm = (str) => {
        if (!str) return '';
        return str.toString()
            .toLowerCase()
            .normalize("NFD")
            .replace(/[\u0300-\u036f]/g, "")
            .replace(/đ/g, "d")
            .replace(/[^a-z0-9]/g, "");
    };

    const keywordConfig = {
        'sku': ['partno', 'partnumber', 'sku', 'code', 'ma', 'masp', 'mahang', 'maphutung', 'mavattu', 'pn', 'ptno'],
        'name': ['partname', 'name', 'ten', 'tensp', 'tenhang', 'description', 'diengiai', 'mota', 'tenvattu'],
        'qty': ['qty', 'quantity', 'soluong', 'slyeucau', 'sl', 'soluongyeucau', 'slthuc', 'slnhap'],
        'tripname': ['trip', 'chuyen', 'sochuyen', 'lotno', 'lot', 'order', 'madon', 'sodonhang'],
        'trno': ['trno', 'tripno', 'sotrip', 'chuyenso', 'tr'],
        'rechh': ['rechh', 'receptacle', 'vikhay', 'binno', 'bin', 'o'],
        'odrtyp': ['odrtyp', 'loaidon', 'ordertype'],
        'pscd': ['pscd', 'quycach', 'packagingstandard', 'packingstandard'],
        'recopr': ['recopr', 'operator', 'nguoilam', 'user'],
        'box': ['box', 'thung'],
        'gate': ['gate', 'cong'],
        'line': ['line', 'chuyen', 'day'],
        'zone': ['zone', 'khu', 'vung', 'khoan']
    };

    const allKeywords = Object.values(keywordConfig).flat();

    // State for parsing
    let activeHeaderMap = null;
    let sectionCounter = 0;
    const itemsToInsert = []; // Array of processed items

    rawData.forEach((row, rowIndex) => {
        if (!row || !Array.isArray(row)) return;

        // Detect if row is a header
        let matchCount = 0;
        row.forEach(cell => {
            if (cell) {
                const s = norm(cell);
                if (allKeywords.includes(s)) matchCount++;
            }
        });

        if (matchCount >= 3) {
            sectionCounter++;
            activeHeaderMap = {};
            row.forEach((cell, idx) => {
                if (cell) {
                    const nKey = norm(cell);
                    if (nKey) activeHeaderMap[nKey] = idx;
                }
            });
            console.log(`[Picking Import] Detected Header at row ${rowIndex + 1}, Section: ${sectionCounter}`);
            console.log('[Picking Import] Active Header Map:', JSON.stringify(activeHeaderMap));
            return;
        }

        if (activeHeaderMap) {
            // Parse columnMapping if provided (it might come as a JSON string)
            let parsedMapping = null;
            if (req.body.columnMapping) {
                try {
                    parsedMapping = typeof req.body.columnMapping === 'string'
                        ? JSON.parse(req.body.columnMapping)
                        : req.body.columnMapping;
                } catch (e) { console.warn('Failed to parse columnMapping', e); }
            }

            const getVal = (type) => {
                // Priority 1: Use explicit column mapping from user
                if (parsedMapping && parsedMapping[type]) {
                    const mappedHeader = parsedMapping[type];
                    // The mapping value corresponds to the header name. 
                    // We need to find the column index for that header in activeHeaderMap.
                    const normHeader = norm(mappedHeader);
                    const colIdx = activeHeaderMap[normHeader];
                    if (colIdx !== undefined && row[colIdx] !== undefined && row[colIdx] !== null) {
                        return row[colIdx];
                    }
                    // If mapped column found but value is null/undefined, return null
                    // But if the header itself wasn't found in this section (maybe section headers differ?), fallback or return null?
                    // Let's fallback to auto-detect if specific mapping fails? No, usually mapping is strict.
                    // However, we'll continue to keyword config if user didn't map this specific field.
                }

                // Priority 2: Auto-detect based on keywords
                if (keywordConfig[type]) {
                    const keys = keywordConfig[type];
                    for (const k of keys) {
                        const colIdx = activeHeaderMap[k];
                        if (colIdx !== undefined && row[colIdx] !== undefined && row[colIdx] !== null) {
                            return row[colIdx];
                        }
                    }
                }
                return null;
            };

            const skuVal = getVal('sku');
            const qtyVal = getVal('qty');

            // --- TIMING LIST SUPPORT ---
            let potentialItems = [];
            const normSelectedDate = selectedDate ? norm(selectedDate) : null;

            if (normSelectedDate && activeHeaderMap[normSelectedDate] !== undefined) {
                // Nếu người dùng chọn đích danh 1 cột tiêu đề
                const dQty = row[activeHeaderMap[normSelectedDate]];
                if (dQty != null && dQty !== "" && !isNaN(parseInt(dQty)) && parseInt(dQty) > 0) {
                    potentialItems.push({
                        qty: parseInt(dQty),
                        suffix: `-${selectedDate}`
                    });
                }
            } else if (qtyVal != null && qtyVal !== "" && !isNaN(parseInt(qtyVal)) && parseInt(qtyVal) > 0) {
                // Standard single-quantity row
                potentialItems.push({
                    qty: parseInt(qtyVal),
                    suffix: ""
                });
            } else {
                // Auto-detect dates if no manual selection or standard qty
                const dateRegex = /^(\d{8}|\d{6}|\d{4}|\d{1,2}[a-z]{3,})$/;
                const dateCols = Object.keys(activeHeaderMap).filter(k => dateRegex.test(k));

                for (const dateKey of dateCols) {
                    if (normSelectedDate && dateKey !== normSelectedDate) continue;
                    const dQty = row[activeHeaderMap[dateKey]];
                    if (dQty != null && dQty !== "" && !isNaN(parseInt(dQty)) && parseInt(dQty) > 0) {
                        potentialItems.push({
                            qty: parseInt(dQty),
                            suffix: `-${dateKey}`
                        });
                    }
                }
            }

            if (skuVal && potentialItems.length > 0) {
                for (const pItem of potentialItems) {
                    const qty = pItem.qty;
                    const suffix = pItem.suffix;

                    // Determine trip/order for this section
                    let tripVal = (getVal('tripname') || getVal('trno') || getVal('rechh') || "").toString().trim();

                    let effectiveBaseOrder = baseOrderNumber && baseOrderNumber.trim() !== "" ? baseOrderNumber : (tripVal || "ORD-AUTO");

                    // Force separation by section or date
                    let rowOrder = tripVal || effectiveBaseOrder;

                    if (suffix) {
                        // For timing lists, we usually want separate orders per date if no specific trip is given
                        // or even if it is, to keep dates distinct.
                        rowOrder = `${rowOrder}${suffix}`;
                    }

                    if (sectionCounter > 1 && !suffix) {
                        if (!tripVal || tripVal === effectiveBaseOrder) {
                            rowOrder = `${effectiveBaseOrder} - P${sectionCounter}`;
                        }
                    }

                    itemsToInsert.push({
                        orderNumber: rowOrder,
                        sku: skuVal.toString().trim(),
                        name: (getVal('name') || 'Unknown').toString().trim(),
                        qty: qty,
                        gate: (getVal('gate') || '').toString(),
                        line: (getVal('line') || '').toString(),
                        zone: (getVal('zone') || '').toString(),
                        rechh: (getVal('rechh') || '').toString(),
                        trno: (getVal('trno') || getVal('tripname') || '').toString(),
                        odrtyp: (getVal('odrtyp') || '').toString(),
                        box: (getVal('box') || '').toString(),
                        pscd: (getVal('pscd') || '').toString(),
                        recopr: (getVal('recopr') || '').toString(),
                        sku_plain: normalizeSku(skuVal)
                    });
                }
            }
        }
    });


    if (itemsToInsert.length === 0) {
        try { fs.unlinkSync(req.file.path); } catch (e) { }
        return res.status(400).json({ error: 'Không tìm thấy dữ liệu hợp lệ trong file Excel.' });
    }

    console.log(`[Picking Import] Processing ${itemsToInsert.length} items across ${sectionCounter} sections.`);

    withTransaction(db, async () => {
        const orderIdMap = new Map(); // orderNumber -> listId
        const orderSummary = [];

        const stmt = db.prepare(`INSERT INTO picking_items (pickingListId, sku, productName, quantityRequired, gate, line, zone, rec_hh, tr_no, odr_typ, box, ps_cd, rec_opr, packagingStandard, sku_plain) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);

        for (const item of itemsToInsert) {
            let currentListId;
            if (orderIdMap.has(item.orderNumber)) {
                currentListId = orderIdMap.get(item.orderNumber);
            } else {
                currentListId = await new Promise((resolve, reject) => {
                    db.get(`SELECT id FROM picking_lists WHERE orderNumber = ? AND customer = ?`, [item.orderNumber, customer], (err, row) => {
                        if (err) return reject(err);
                        if (row) {
                            resolve(row.id);
                        } else {
                            db.run(`INSERT INTO picking_lists (orderNumber, customer, status, createdAt) VALUES (?, ?, 'pending', ?)`,
                                [item.orderNumber, customer, new Date().toISOString()],
                                function (insErr) {
                                    if (insErr) reject(insErr); else resolve(this.lastID);
                                });
                        }
                    });
                });
                orderIdMap.set(item.orderNumber, currentListId);
            }

            // Track summary
            let summary = orderSummary.find(s => s.orderNumber === item.orderNumber);
            if (!summary) {
                summary = { orderNumber: item.orderNumber, count: 0, qty: 0 };
                orderSummary.push(summary);
            }
            summary.count++;
            summary.qty += item.qty;

            await new Promise((resolveInsert, rejectInsert) => {
                stmt.run(
                    currentListId, item.sku, item.name, item.qty,
                    item.gate, item.line, item.zone, item.rechh, item.trno, item.odrtyp,
                    item.box, item.pscd, item.recopr,
                    (item.pscd || '').toString(), item.sku_plain,
                    (err) => {
                        if (err) rejectInsert(err); else resolveInsert();
                    }
                );
            });
        }

        stmt.finalize();
        try { fs.unlinkSync(req.file.path); } catch (e) { }

        res.json({
            success: true,
            totalItems: itemsToInsert.length,
            orderCount: orderIdMap.size,
            orders: orderSummary,
            totalQuantity: orderSummary.reduce((acc, s) => acc + s.qty, 0)
        });
    }).catch(err => {
        console.error("[Picking Import] ERROR:", err);
        if (req.file && fs.existsSync(req.file.path)) {
            try { fs.unlinkSync(req.file.path); } catch (e) { }
        }
        res.status(500).json({ error: err.message || 'Lỗi hệ thống khi xử lý file Excel' });
    });
});


app.post('/api/picking/assign', (req, res) => {
    const { listId, username, recs, trs, gates, lines, zones, typs, boxes, pscds, oprs } = req.body;
    console.log(`[POST /api/picking/assign] List: ${listId}, TargetUser: ${username}`);

    if (!listId || !username) return res.status(400).json({ error: 'Missing listId or username' });

    let filters = ['pickingListId = ?'];
    let params = [listId];

    const addArrFilter = (col, arr) => {
        if (arr && Array.isArray(arr) && arr.length > 0) {
            filters.push(`TRIM(UPPER(${col})) IN (${arr.map(() => '?').join(',')})`);
            params.push(...arr.map(s => s.toString().trim().toUpperCase()));
        }
    };

    addArrFilter('rec_hh', recs);
    addArrFilter('tr_no', trs);
    addArrFilter('gate', gates);
    addArrFilter('line', lines);
    addArrFilter('zone', zones);
    addArrFilter('odr_typ', typs);
    addArrFilter('box', boxes);
    addArrFilter('ps_cd', pscds);

    if (oprs && Array.isArray(oprs) && oprs.length > 0) {
        const oprFilters = oprs.map(() => `TRIM(UPPER(rec_opr)) LIKE ?`).join(' OR ');
        filters.push(`(${oprFilters})`);
        params.push(...oprs.map(o => o.toString().trim().toUpperCase() + '%'));
    }

    const query = `UPDATE picking_items SET assigned_user = ? WHERE ${filters.join(' AND ')}`;
    db.run(query, [username, ...params], function (err) {
        if (err) return res.status(500).json({ error: err.message });
        console.log(`[ASSIGN SUCCESS] Updated ${this.changes} items for user ${username}`);
        res.json({ message: 'Assigned successfully', count: this.changes });
    });
});

app.delete('/api/picking/:id', (req, res) => {
    const listId = req.params.id;
    db.serialize(() => {
        db.run(`DELETE FROM picking_items WHERE pickingListId = ?`, [listId]);
        db.run(`DELETE FROM picking_lists WHERE id = ?`, [listId], function (err) {
            if (err) return res.status(500).json({ error: err.message });
            res.json({ message: 'Order deleted' });
        });
    });
});

app.put('/api/picking/item/:id', (req, res) => {
    const { quantityPicked, username } = req.body;

    if (!username) {
        return res.status(400).json({ error: 'Username is required for security verification' });
    }

    db.get(`SELECT * FROM picking_items WHERE id = ?`, [req.params.id], (err, item) => {
        if (err) return res.status(500).json({ error: err.message });
        if (!item) return res.status(404).json({ error: 'Item not found' });

        db.get(`SELECT * FROM users WHERE username = ?`, [username], (err, user) => {
            if (err) return res.status(500).json({ error: err.message });
            if (!user) return res.status(401).json({ error: 'User not found' });

            // Admin bypass
            if (user.role === 'admin') {
                return performUpdate();
            }

            // Permission check
            // Permission check: Verify trip-specific assignment
            const isAllowed = item.assigned_user && item.assigned_user.trim().toUpperCase() === username.trim().toUpperCase();

            if (!isAllowed) {
                console.warn(`[SECURITY] User ${username} unauthorized attempt to pick item ${item.sku} in order ${item.pickingListId}. Assigned to: ${item.assigned_user}`);
                return res.status(403).json({ error: 'Bạn không có quyền soạn mã hàng này (Mã này chưa được gán cho bạn trong đơn này).' });
            }

            performUpdate();

            function performUpdate() {
                db.run(`UPDATE picking_items SET quantityPicked = ? WHERE id = ?`, [quantityPicked, req.params.id], function (err) {
                    if (err) return res.status(500).json({ error: err.message });
                    res.json({ message: 'Updated successfully' });
                });
            }
        });
    });
});


app.put('/api/picking/status/:id', (req, res) => {
    const { status } = req.body;
    db.run(`UPDATE picking_lists SET status = ? WHERE id = ?`, [status, req.params.id], function (err) {
        if (err) return res.status(500).json({ error: err.message });
        res.json({ message: 'Status updated' });
    });
});


// Routes

// Auth
// Auth
// Auth
app.post('/api/login', (req, res) => {
    const { username, password } = req.body;
    console.log(`[LOGIN ATTEMPT] User: ${username}`);

    if (!username || !password) {
        return res.status(400).json({ error: 'Username and password required' });
    }

    const hashedPassword = crypto.createHash('sha256').update(password).digest('hex');

    db.get(`SELECT * FROM users WHERE username = ?`, [username], (err, row) => {
        if (err) {
            console.error('Login DB error:', err);
            return res.status(500).json({ error: 'Database error' });
        }

        if (row && row.password === hashedPassword) {
            const { password, ...userWithoutPassword } = row;
            console.log(`[LOGIN SUCCESS] User: ${username}, Role: ${row.role}`);
            return res.json(userWithoutPassword);
        } else {
            console.log(`[LOGIN FAILED] User: ${username}`);
            return res.status(401).json({ error: 'Tài khoản hoặc mật khẩu không chính xác' });
        }
    });
});

// Products
app.get('/api/products', (req, res) => {
    db.all(`SELECT * FROM products`, [], (err, rows) => {
        if (err) return res.status(500).json({ error: err.message });
        console.log(`[GET /api/products] Returning ${rows.length} products`);
        res.json(rows);
    });
});

app.get('/api/products/:sku', (req, res) => {
    const sku = req.params.sku;
    const sku_plain = normalizeSku(sku);
    db.get(`SELECT * FROM products WHERE sku = ? OR sku_plain = ?`, [sku, sku_plain], (err, row) => {
        if (err) return res.status(500).json({ error: err.message });
        if (row) res.json(row);
        else res.status(404).json({ error: 'Product not found' });
    });
});


app.post('/api/products', upload.fields([{ name: 'image', maxCount: 1 }, { name: 'image2', maxCount: 1 }]), (req, res) => {
    const { sku, name, packagingStandard, layoutPosition, customer, description, stock } = req.body;
    const imageUrl = req.files['image'] ? `/uploads/${req.files['image'][0].filename}` : null;
    const imageUrl2 = req.files['image2'] ? `/uploads/${req.files['image2'][0].filename}` : null;
    db.run(`INSERT INTO products (sku, sku_plain, name, packagingStandard, imageUrl, layoutPosition, customer, description, imageUrl2, stock) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [sku, normalizeSku(sku), name, packagingStandard, imageUrl, layoutPosition, customer, description, imageUrl2, stock || 0],
        function (err) {
            if (err) return res.status(500).json({ error: err.message });
            res.json({ id: this.lastID });
        }
    );

});

app.put('/api/products/:id', upload.fields([{ name: 'image', maxCount: 1 }, { name: 'image2', maxCount: 1 }]), (req, res) => {
    const { sku, name, packagingStandard, layoutPosition, customer, description, stock } = req.body;
    let query = `UPDATE products SET sku=?, sku_plain=?, name=?, packagingStandard=?, layoutPosition=?, customer=?, description=?, stock=?`;
    let params = [sku, normalizeSku(sku), name, packagingStandard, layoutPosition, customer, description, stock || 0];


    if (req.files['image']) {
        query += `, imageUrl=?`;
        params.push(`/uploads/${req.files['image'][0].filename}`);
    }
    if (req.files['image2']) {
        query += `, imageUrl2=?`;
        params.push(`/uploads/${req.files['image2'][0].filename}`);
    }

    query += ` WHERE id=?`;
    params.push(req.params.id);

    db.run(query, params, function (err) {
        if (err) return res.status(500).json({ error: err.message });
        res.json({ message: 'Updated' });
    });
});

app.delete('/api/products/:id', (req, res) => {
    db.run(`DELETE FROM products WHERE id = ?`, [req.params.id], function (err) {
        if (err) return res.status(500).json({ error: err.message });
        res.json({ message: 'Deleted' });
    });
});

// Users
app.get('/api/users', (req, res) => {
    db.all(`SELECT id, username, role, assignedRecs, assignedTyps, assignedPs, assignedOprs, assignedTr, assignedGate, assignedLine, assignedZone, assignedBox FROM users`, [], (err, rows) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json(rows);
    });
});

app.post('/api/users', (req, res) => {
    const { username, password, role, assignedRecs, assignedTyps, assignedPs, assignedOprs, assignedTr, assignedGate, assignedLine, assignedZone, assignedBox } = req.body;
    const hashed = crypto.createHash('sha256').update(password).digest('hex');
    db.run(`INSERT INTO users (username, password, role, assignedRecs, assignedTyps, assignedPs, assignedOprs, assignedTr, assignedGate, assignedLine, assignedZone, assignedBox) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [username, hashed, role, assignedRecs, assignedTyps, assignedPs, assignedOprs, assignedTr, assignedGate, assignedLine, assignedZone, assignedBox], function (err) {
            if (err) return res.status(500).json({ error: err.message });
            res.json({ id: this.lastID });
        });
});

app.put('/api/users/:id', (req, res) => {
    const { password, role, assignedRecs, assignedTyps, assignedPs, assignedOprs, assignedTr, assignedGate, assignedLine, assignedZone, assignedBox } = req.body;
    if (password) {
        const hashed = crypto.createHash('sha256').update(password).digest('hex');
        db.run(`UPDATE users SET password = ?, role = ?, assignedRecs = ?, assignedTyps = ?, assignedPs = ?, assignedOprs = ?, assignedTr = ?, assignedGate = ?, assignedLine = ?, assignedZone = ?, assignedBox = ? WHERE id = ?`,
            [hashed, role, assignedRecs, assignedTyps, assignedPs, assignedOprs, assignedTr, assignedGate, assignedLine, assignedZone, assignedBox, req.params.id], (err) => {
                if (err) return res.status(500).json({ error: err.message });
                res.json({ message: 'User updated' });
            });
    } else {
        db.run(`UPDATE users SET role = ?, assignedRecs = ?, assignedTyps = ?, assignedPs = ?, assignedOprs = ?, assignedTr = ?, assignedGate = ?, assignedLine = ?, assignedZone = ?, assignedBox = ? WHERE id = ?`,
            [role, assignedRecs, assignedTyps, assignedPs, assignedOprs, assignedTr, assignedGate, assignedLine, assignedZone, assignedBox, req.params.id], (err) => {
                if (err) return res.status(500).json({ error: err.message });
                res.json({ message: 'User updated' });
            });
    }
});

app.delete('/api/users/:id', (req, res) => {
    db.run(`DELETE FROM users WHERE id = ?`, [req.params.id], function (err) {
        if (err) return res.status(500).json({ error: err.message });
        res.json({ message: 'Deleted' });
    });
});

// Logs
app.get('/api/logs', (req, res) => {
    db.all(`SELECT * FROM logs ORDER BY timestamp DESC`, [], (err, rows) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json(rows);
    });
});

app.post('/api/logs', (req, res) => {
    const { username, action, details, timestamp } = req.body;
    db.run(`INSERT INTO logs (username, action, details, timestamp) VALUES (?, ?, ?, ?)`, [username, action, details, timestamp], function (err) {
        if (err) return res.status(500).json({ error: err.message });
        res.json({ id: this.lastID });
    });
});

app.delete('/api/logs/all', (req, res) => {
    db.run(`DELETE FROM logs`, [], function (err) {
        if (err) return res.status(500).json({ error: err.message });
        res.json({ message: 'All logs deleted' });
    });
});

app.post('/api/logs/delete-multiple', (req, res) => {
    const { ids } = req.body;
    if (!ids || !Array.isArray(ids)) return res.status(400).json({ error: 'IDs array required' });

    const placeholders = ids.map(() => '?').join(',');
    db.run(`DELETE FROM logs WHERE id IN (${placeholders})`, ids, function (err) {
        if (err) return res.status(500).json({ error: err.message });
        res.json({ message: `${this.changes} logs deleted` });
    });
});

app.delete('/api/logs/:id', (req, res) => {
    db.run(`DELETE FROM logs WHERE id = ?`, [req.params.id], function (err) {
        if (err) return res.status(500).json({ error: err.message });
        res.json({ message: 'Log deleted' });
    });
});

// Stock Audit
app.post('/api/stock-audit', (req, res) => {
    const { sku, packagingStandard, horRows, verRows, evenRows, oddRows, individualBags, totalResult, auditor, timestamp } = req.body;
    const sku_plain = normalizeSku(sku);
    const query = `INSERT INTO stock_audit (sku, sku_plain, packagingStandard, horRows, verRows, evenRows, oddRows, individualBags, totalResult, auditor, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;
    db.run(query, [sku, sku_plain, packagingStandard, horRows, verRows, evenRows, oddRows, individualBags, totalResult, auditor, timestamp], function (err) {
        if (err) return res.status(500).json({ error: err.message });
        res.json({ id: this.lastID });
    });

});

app.get('/api/stock-audit', (req, res) => {
    db.all(`SELECT * FROM stock_audit ORDER BY timestamp DESC`, [], (err, rows) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json(rows);
    });
});

// Moved /api/stock-audit/:id to bottom to use syncStockAfterAuditChange helper

// ========================================
// OPTIMIZED ENDPOINTS WITH CONCURRENCY SAFETY
// ========================================

/**
 * Update Stock Audit with Optimistic Locking
 * Prevents race conditions when multiple users audit the same SKU
 */
app.put('/api/stock-audit/safe-update', async (req, res) => {
    const { sku, warehouse, updates, auditor } = req.body;

    if (!sku || !updates || auditor === undefined) {
        return res.status(400).json({
            error: 'Missing required fields: sku, updates, auditor'
        });
    }
    const now = new Date().toISOString();
    const totalResult = updates.totalResult || 0;
    const location = updates.location || '';

    try {
        await withTransaction(db, async () => {
            // 1. Determine the correct warehouse and find/create the ERP record
            let erpRow = await new Promise((resolve, reject) => {
                const sku_plain = normalizeSku(sku);
                // If warehouse is empty or "Default", try to find any existing warehouse for this SKU
                if (!warehouse || warehouse === 'Default') {
                    db.get('SELECT * FROM erp_stock WHERE sku = ? OR sku_plain = ? LIMIT 1', [sku, sku_plain], (err, row) => {
                        if (err) reject(err); else resolve(row);
                    });
                } else {
                    db.get('SELECT * FROM erp_stock WHERE (sku = ? OR sku_plain = ?) AND warehouse = ?', [sku, sku_plain, warehouse], (err, row) => {
                        if (err) reject(err); else resolve(row);
                    });
                }
            });


            const effectiveWarehouse = erpRow ? erpRow.warehouse : (warehouse || 'Default');
            const effectiveSkuAtDb = erpRow ? erpRow.sku : sku;


            // 2. Ensure ERP stock record exists
            if (!erpRow) {
                await new Promise((resolve, reject) => {
                    db.run(
                        'INSERT INTO erp_stock (sku, sku_plain, warehouse, quantity, updatedAt, version) VALUES (?, ?, ?, ?, ?, ?)',
                        [sku, normalizeSku(sku), effectiveWarehouse, '0', now, 1],
                        function (err) {
                            if (err) reject(err); else resolve(this.lastID);
                        }
                    );
                });

                // Re-fetch to get current state
                erpRow = {
                    sku, warehouse: effectiveWarehouse, quantity: '0',
                    kk1: '0', kk2: '0', kk3: '0', kk4: '0', kk5: '0',
                    kk6: '0', kk7: '0', kk8: '0', kk9: '0', kk10: '0',
                    total_kk: 0
                };
            }

            // 3. Find the first empty KK slot and calculate new totals
            // Requirement: "thứ tự lần lượt dữ liệu đến trước ghi trước đến sau ghi sau"
            let targetSlot = null;
            let currentKkValues = [];
            for (let i = 1; i <= 10; i++) {
                const val = erpRow[`kk${i}`] || '0';
                currentKkValues.push(val);
                if (targetSlot === null && (val === '0' || val === '' || val === 0)) {
                    targetSlot = i;
                }
            }

            // If all slots are full, overwrite the last one or just keep as is? 
            // Better to fill slot 10 if all full, or just stop filling slots but keep updating total.
            // Let's stick to the first 10.
            const actualSlot = targetSlot || 10;

            // Calculate new total KK
            let totalKk = 0;
            for (let i = 1; i <= 10; i++) {
                let val = parseFloat(erpRow[`kk${i}`]) || 0;
                if (i === actualSlot) val = totalResult; // Use new value for the target slot
                totalKk += val;
            }

            const erpQty = parseFloat((erpRow.quantity || '0').toString().replace(/,/g, '')) || 0;
            const diff = totalKk - erpQty;

            // 4. Update ERP Stock
            const erpUpdateQuery = `
                UPDATE erp_stock SET 
                kk${actualSlot} = ?,
                total_kk = ?,
                difference = ?,
                updatedAt = ?,
                version = version + 1
                WHERE sku = ? AND warehouse = ?
            `;

            await new Promise((resolve, reject) => {
                db.run(erpUpdateQuery, [
                    totalResult.toString(), totalKk, diff, now, effectiveSkuAtDb, effectiveWarehouse
                ], (err) => {
                    if (err) reject(err); else resolve();
                });
            });

            // 5. Insert into stock_audit history
            await new Promise((resolve, reject) => {
                db.run(
                    `INSERT INTO stock_audit (sku, sku_plain, warehouse, location, packagingStandard, horRows, verRows, evenRows, oddRows, individualBags, totalResult, auditor, timestamp, version) 
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                    [
                        effectiveSkuAtDb, normalizeSku(effectiveSkuAtDb), effectiveWarehouse, location,
                        updates.packagingStandard || 0,
                        updates.horRows || 0,
                        updates.verRows || 0,
                        updates.evenRows || 0,
                        updates.oddRows || 0,
                        updates.individualBags || 0,
                        totalResult, auditor, now, 1
                    ],
                    function (err) {
                        if (err) reject(err); else resolve(this.lastID);
                    }
                );
            });


            // Broadcast updates
            io.emit('erp_update', { sku, warehouse: effectiveWarehouse });
            io.emit('stock_audit_updated', { sku, warehouse: effectiveWarehouse, auditor });
        });

        res.json({
            success: true,
            message: 'Đã ghi nhận kết quả kiểm kê.'
        });

    } catch (err) {
        console.error('[PUT /api/stock-audit/safe-update] Error:', err);
        res.status(500).json({ error: err.message });
    }
});

/**
 * Update ERP Stock with Optimistic Locking
 * Prevents data corruption when multiple users update same SKU
 */
app.put('/api/erp/safe-update', async (req, res) => {
    const { sku, warehouse, updates, version, userId } = req.body;

    if (!sku || !warehouse || !updates || version === undefined || !userId) {
        return res.status(400).json({
            error: 'Missing required fields: sku, warehouse, updates, version, userId'
        });
    }

    try {
        const result = await updateErpStock(db, sku, warehouse, updates, version, userId);

        if (result.success) {
            // Broadcast update via Socket.IO
            io.emit('erp_stock_updated', { sku, warehouse, userId });

            // Log audit
            logAudit(db, 'erp_stock', `${sku}_${warehouse}`, 'UPDATE',
                null, updates, userId, req.ip);

            res.json({
                success: true,
                message: 'ERP stock updated successfully'
            });
        } else if (result.conflict) {
            res.status(409).json({
                error: 'Version conflict',
                message: 'Dữ liệu đã được cập nhật bởi người khác. Vui lòng tải lại.',
                currentVersion: result.currentVersion
            });
        } else if (result.notFound) {
            res.status(404).json({
                error: 'Not found',
                message: 'Không tìm thấy SKU trong kho ERP'
            });
        }
    } catch (err) {
        console.error('[PUT /api/erp/safe-update] Error:', err);
        res.status(500).json({ error: err.message });
    }
});

/**
 * Claim Notification (Exclusive)
 * Ensures only one user can claim a "KIỂM TRA NGAY" notification
 */
app.post('/api/notifications/claim/:id', async (req, res) => {
    const { userId } = req.body;
    const notificationId = parseInt(req.params.id);

    if (!userId) {
        return res.status(400).json({ error: 'Missing userId' });
    }

    if (isNaN(notificationId)) {
        return res.status(400).json({ error: 'Invalid notification ID' });
    }

    try {
        const claimed = await claimNotification(db, notificationId, userId);

        if (claimed) {
            // Broadcast to all clients to remove notification from their UI
            io.emit('notification_claimed', {
                id: notificationId,
                claimedBy: userId,
                timestamp: new Date().toISOString()
            });

            // Log audit
            logAudit(db, 'notifications', notificationId.toString(), 'CLAIM',
                null, { claimed_by: userId }, userId, req.ip);

            res.json({
                success: true,
                message: 'Notification claimed successfully'
            });
        } else {
            res.status(409).json({
                error: 'Already claimed',
                message: 'Thông báo đã được xử lý bởi người khác'
            });
        }
    } catch (err) {
        console.error('[POST /api/notifications/claim] Error:', err);
        res.status(500).json({ error: err.message });
    }
});

/**
 * Batch Update with Transaction
 * Safely update multiple records in a single transaction
 */
app.post('/api/batch-update', async (req, res) => {
    const { operations, userId } = req.body;

    if (!operations || !Array.isArray(operations) || !userId) {
        return res.status(400).json({
            error: 'Missing required fields: operations (array), userId'
        });
    }

    try {
        await withTransaction(db, async () => {
            for (const op of operations) {
                const { table, sku, warehouse, updates, version } = op;

                if (table === 'erp_stock') {
                    const result = await updateErpStock(db, sku, warehouse, updates, version, userId);
                    if (!result.success) {
                        throw new Error(`Failed to update ${sku}: ${result.conflict ? 'Version conflict' : 'Not found'}`);
                    }
                } else if (table === 'stock_audit') {
                    const result = await updateStockAudit(db, sku, warehouse, updates, version, userId);
                    if (!result.success) {
                        throw new Error(`Failed to update audit ${sku}: ${result.conflict ? 'Version conflict' : 'Not found'}`);
                    }
                }
            }
        });

        res.json({
            success: true,
            message: `Successfully updated ${operations.length} records`
        });
    } catch (err) {
        console.error('[POST /api/batch-update] Error:', err);
        res.status(500).json({
            error: err.message,
            message: 'Batch update failed. All changes rolled back.'
        });
    }
});

/**
 * Get Audit Log
 * View history of all changes for debugging/compliance
 */
app.get('/api/audit-log', (req, res) => {
    const { table, recordId, userId, limit = 100, offset = 0 } = req.query;

    let whereClause = [];
    let params = [];

    if (table) {
        whereClause.push('table_name = ?');
        params.push(table);
    }
    if (recordId) {
        whereClause.push('record_id = ?');
        params.push(recordId);
    }
    if (userId) {
        whereClause.push('user_id = ?');
        params.push(userId);
    }

    const where = whereClause.length > 0 ? 'WHERE ' + whereClause.join(' AND ') : '';

    const sql = `
        SELECT * FROM audit_log
        ${where}
        ORDER BY created_at DESC
        LIMIT ? OFFSET ?
    `;

    params.push(parseInt(limit), parseInt(offset));

    db.all(sql, params, (err, rows) => {
        if (err) {
            console.error('[GET /api/audit-log] Error:', err);
            return res.status(500).json({ error: err.message });
        }

        res.json({
            logs: rows,
            limit: parseInt(limit),
            offset: parseInt(offset)
        });
    });
});





app.get('/api/admin/assignment-progress', (req, res) => {
    db.all(`SELECT id, username, role, assignedRecs, assignedTyps, assignedPs, assignedOprs, assignedTr, assignedGate, assignedLine, assignedZone, assignedBox FROM users WHERE role = 'user'`, [], async (err, users) => {
        if (err) return res.status(500).json({ error: err.message });

        const results = [];

        for (const user of users) {
            let whereClause = '';
            let params = [];
            let filters = [];

            if (user.assignedRecs && user.assignedRecs.trim()) {
                const recList = user.assignedRecs.split(',').map(s => s.trim().toUpperCase());
                filters.push(`TRIM(UPPER(rec_hh)) IN (${recList.map(() => '?').join(',')})`);
                params.push(...recList);
            }
            if (user.assignedTyps && user.assignedTyps.trim()) {
                const typList = user.assignedTyps.split(',').map(s => s.trim().toUpperCase());
                filters.push(`TRIM(UPPER(odr_typ)) IN (${typList.map(() => '?').join(',')})`);
                params.push(...typList);
            }
            if (user.assignedPs && user.assignedPs.trim()) {
                const psList = user.assignedPs.split(',').map(s => s.trim().toUpperCase());
                filters.push(`TRIM(UPPER(ps_cd)) IN (${psList.map(() => '?').join(',')})`);
                params.push(...psList);
            }
            if (user.assignedOprs && user.assignedOprs.trim()) {
                const oprList = user.assignedOprs.split(',').map(s => s.trim().toUpperCase());
                const oprFilters = oprList.map(() => `TRIM(UPPER(rec_opr)) LIKE ?`).join(' OR ');
                filters.push(`(${oprFilters})`);
                params.push(...oprList.map(o => o + '%'));
            }

            if (filters.length > 0) {
                whereClause = 'WHERE ' + filters.join(' AND ');

                try {
                    const stats = await new Promise((resolve, reject) => {
                        const query = `
                            SELECT 
                                COUNT(id) as totalItems,
                                SUM(quantityRequired) as totalQtyRequired,
                                SUM(quantityPicked) as totalQtyPicked
                            FROM picking_items
                            ${whereClause}
                        `;
                        db.get(query, params, (err, row) => {
                            if (err) reject(err);
                            else resolve(row);
                        });
                    });

                    results.push({
                        ...user,
                        stats: stats || { totalItems: 0, totalQtyRequired: 0, totalQtyPicked: 0 }
                    });
                } catch (e) {
                    results.push({ ...user, stats: { totalItems: 0, totalQtyRequired: 0, totalQtyPicked: 0, error: e.message } });
                }
            } else {
                results.push({
                    ...user,
                    stats: { totalItems: 0, totalQtyRequired: 0, totalQtyPicked: 0, message: 'No assignments' }
                });
            }
        }

        res.json(results);
    });
});

// System Settings
app.get('/api/settings', (req, res) => {
    db.all(`SELECT * FROM system_settings`, [], (err, rows) => {
        if (err) return res.status(500).json({ error: err.message });
        const settings = {};
        rows.forEach(row => settings[row.key] = row.value);
        res.json(settings);
    });
});

app.post('/api/settings', (req, res) => {
    const { key, value } = req.body;
    if (!key) return res.status(400).json({ error: 'Key required' });
    db.run(`INSERT OR REPLACE INTO system_settings (key, value) VALUES (?, ?)`, [key, value], function (err) {
        if (err) return res.status(500).json({ error: err.message });
        io.emit('settings_updated', { key, value });
        res.json({ message: 'Setting updated' });
    });
});

const os = require('os');

function getLocalIp() {
    const interfaces = os.networkInterfaces();
    for (const devName in interfaces) {
        const iface = interfaces[devName];
        for (let i = 0; i < iface.length; i++) {
            const alias = iface[i];
            if (alias.family === 'IPv4' && alias.address !== '127.0.0.1' && !alias.internal) {
                return alias.address;
            }
        }
    }
    return 'localhost';
}

app.get('/api/erp/warehouses', (req, res) => {
    db.all(`SELECT DISTINCT warehouse FROM erp_stock WHERE warehouse IS NOT NULL AND warehouse != ''`, [], (err, rows) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json(rows.map(r => r.warehouse));
    });
});

app.get('/api/erp/stock', (req, res) => {
    const { warehouse, search, limit, offset } = req.query;
    let query = `SELECT * FROM erp_stock`;
    let countQuery = `SELECT COUNT(*) as total FROM erp_stock`;
    let params = [];
    let conditions = [];

    if (warehouse && warehouse.trim()) {
        conditions.push(`warehouse = ?`);
        params.push(warehouse);
    }

    if (search && search.trim()) {
        conditions.push(`(sku LIKE ? OR name LIKE ?)`);
        params.push(`%${search}%`, `%${search}%`);
    }

    const whereClause = conditions.length > 0 ? ` WHERE ${conditions.join(' AND ')}` : '';
    query += whereClause;
    countQuery += whereClause;

    query += ` ORDER BY id ASC`;

    // Add pagination
    const pageLimit = parseInt(limit) || 200; // Default 200 rows per page
    const pageOffset = parseInt(offset) || 0;
    query += ` LIMIT ${pageLimit} OFFSET ${pageOffset}`;

    // Get total count first
    db.get(countQuery, params, (err, countRow) => {
        if (err) return res.status(500).json({ error: err.message });

        // Then get paginated data
        db.all(query, params, (err, rows) => {
            if (err) return res.status(500).json({ error: err.message });
            res.json({
                data: rows,
                total: countRow.total,
                limit: pageLimit,
                offset: pageOffset,
                hasMore: (pageOffset + rows.length) < countRow.total
            });
        });
    });
});

app.post('/api/erp/sync', async (req, res) => {
    const { date, warehouse } = req.body;
    console.log(`[ERP] Yêu cầu đồng bộ dữ liệu: Ngày=${date}, Kho=${warehouse}`);

    if (!puppeteer) {
        return res.status(500).json({ error: 'Hệ thống đang chuẩn bị Puppeteer. Vui lòng thử lại sau.' });
    }

    let browser;
    const downloadPath = path.join(__dirname, 'uploads', 'erp_exports_' + Date.now());
    if (!fs.existsSync(downloadPath)) fs.mkdirSync(downloadPath, { recursive: true });

    const userDataDir = path.join(os.tmpdir(), 'puppeteer_user_data_' + Date.now());

    const syncMarker = new Date().toISOString();
    const progress = (status, percent) => {
        io.emit('erp_sync_progress', { status, percent, warehouse: warehouse || 'All' });
        console.log(`[ERP Sync] ${status} (${Math.round(percent * 100)}%)`);
    };

    try {
        progress('Khởi tạo trình duyệt...', 0.05);
        browser = await puppeteer.launch({
            headless: true,
            args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage', '--start-maximized'],
            executablePath: process.env.PUPPETEER_EXECUTABLE_PATH || process.env.CHROME_PATH || "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
            userDataDir: userDataDir
        });

        const page = await browser.newPage();
        page.on('console', msg => console.log('BROWSER LOG:', msg.text()));

        const client = await page.target().createCDPSession();
        await client.send('Page.setDownloadBehavior', {
            behavior: 'allow',
            downloadPath: downloadPath
        });

        page.setDefaultTimeout(60000);

        // --- 1. Login Logic ---
        progress('Kiểm tra trạng thái đăng nhập...', 0.1);
        await page.goto('http://113.161.136.106:97/RapidIS/Default.aspx', { waitUntil: 'networkidle2' });

        // Check if on login page
        const isLoginPage = await page.evaluate(() => {
            return !!document.querySelector('#A2UserID') || !!document.querySelector('input[name="A2UserID"]') || document.title.includes('Login');
        });

        if (isLoginPage) {
            progress('Đang thực hiện đăng nhập...', 0.15);
            const username = 'anchor\\AFS1757';
            const password = 'hAnoi89@';

            try {
                // Wait for any input to be ready
                await page.waitForSelector('input[name="A2UserID"], #A2UserID', { timeout: 10000 });
                const userSel = (await page.$('#A2UserID')) ? '#A2UserID' : 'input[name="A2UserID"]';
                const passSel = (await page.$('#A2Password')) ? '#A2Password' : 'input[name="A2Password"]';
                const submitSel = (await page.$('#login_form_submit')) ? '#login_form_submit' : 'input[type="submit"]';

                await page.type(userSel, username);
                await page.type(passSel, password);

                await Promise.all([
                    page.click(submitSel),
                    page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 60000 }).catch(e => console.log('Nav timeout ignorable'))
                ]);
                console.log('Login credentials submitted.');
            } catch (e) {
                console.error('Lỗi khi điền form đăng nhập:', e.message);
                // Try proceeding anyway, maybe false positive
            }
        } else {
            console.log('[ERP] Đã đăng nhập hoặc không ở trang login.');
        }

        // --- 2. Navigate to Report ---
        progress('Chuyển đến trang báo cáo...', 0.25);
        const directReportUrl = 'http://113.161.136.106:97/RapidIS/default.aspx?A2ProcessName=Warehouse&A2Option=AutoSearch&TabName=WarehousingReports%2C%3B%2CSearchPrintPIONew&Action=Edit&A2RstName=A2Company';
        await page.goto(directReportUrl, { waitUntil: 'networkidle0', timeout: 60000 });
        await new Promise(r => setTimeout(r, 3000));

        // --- 3. Fill Parameters ---
        let dateToFill = date;
        if (!dateToFill) {
            const today = new Date();
            dateToFill = `${today.getFullYear()}/${String(today.getMonth() + 1).padStart(2, '0')}/${String(today.getDate()).padStart(2, '0')}`;
        }
        progress(`Điền tham số: ${dateToFill} | ${warehouse || 'Tất cả'}`, 0.3);

        // Robust Input Filling
        const fillInput = async (selectors, value) => {
            for (const sel of selectors) {
                if (await page.$(sel)) {
                    await page.$eval(sel, (el, v) => el.value = v, value);
                    return true;
                }
            }
            return false;
        };

        if (dateToFill) await fillInput(['input[name="NewScheduleDate"]', 'input[id*="ScheduleDate"]'], dateToFill);
        if (warehouse) await fillInput(['input[name="NewWarehouse"]', 'input[id*="Warehouse"]'], warehouse);

        // --- 4. Click Print ---
        progress('Đang chạy báo cáo...', 0.35);
        let printBtn = await page.$('button[name="SearchPrintPIONew"]');
        if (!printBtn) printBtn = await page.$('button.sbttn');

        // Fallback: Find by Text
        if (!printBtn) {
            const buttons = await page.$$('button');
            for (const btn of buttons) {
                const text = await page.evaluate(el => el.innerText, btn);
                if (text.includes('In') || text.includes('Print')) {
                    printBtn = btn;
                    console.log(`Found Print button by text: ${text}`);
                    break;
                }
            }
        }

        if (printBtn) {
            await Promise.all([
                printBtn.click(),
                // Wait for potential page reload or just delay
                new Promise(r => setTimeout(r, 5000))
            ]);
        } else {
            console.warn("KHÔNG TÌM THẤY NÚT 'IN'. Sẽ thử dùng Enter...");
            const whInput = await page.$('input[name="NewWarehouse"]');
            if (whInput) {
                await whInput.press('Enter');
                await new Promise(r => setTimeout(r, 5000));
            }
        }

        progress('Đang đợi hệ thống render báo cáo (10s)...', 0.45);
        await new Promise(r => setTimeout(r, 10000));

        // --- 5. Export Strategy with Fallback ---
        const exportBtnSelectors = [
            '#CrystalReportViewer1_toptoolbar_export',
            'img[title="Export this report"]',
            'a[title="Export this report"]',
            '[id*="toptoolbar_export"]',
            'input[title="Export this report"]'
        ];

        let exportBtn = null;
        progress('Đang tìm nút Export...', 0.55);
        for (let attempt = 1; attempt <= 15; attempt++) {
            for (const sel of exportBtnSelectors) {
                const el = await page.$(sel);
                if (el) { exportBtn = el; break; }
            }
            if (exportBtn) break;
            await new Promise(r => setTimeout(r, 2000));
        }

        const data = []; // Results container

        if (exportBtn) {
            progress('Đang tiến hành xuất Excel...', 0.65);
            await page.evaluate(el => el.click(), exportBtn);
            await new Promise(r => setTimeout(r, 4000));

            // Automation of Dialog ... (Simplified version of previous)
            // ... Keyboard nav ...
            // Assuming previous logic worked when button was found.
            // Implemening the critical key presses:
            await page.keyboard.press('Tab'); await page.keyboard.press('Space'); // Open Combo
            await new Promise(r => setTimeout(r, 1000));
            for (let k = 0; k < 20; k++) { // Find Excel
                await page.keyboard.press('ArrowDown');
                const txt = await page.evaluate(() => document.activeElement.innerText || '');
                if (txt.includes('Excel') && txt.includes('Data-Only')) {
                    await page.keyboard.press('Enter'); break;
                }
            }
            await page.keyboard.press('Enter'); // Close combo / Select

            // Find Export button
            for (let k = 0; k < 15; k++) {
                await page.keyboard.press('Tab');
                const txt = await page.evaluate(() => document.activeElement.innerText || document.activeElement.value || '');
                if (txt === 'Export') { await page.keyboard.press('Enter'); break; }
            }

            // Wait for file
            // ... (Re-using generic wait logic implicitly or skipping to parsing)
            progress('Đang đợi tải tệp xuống...', 0.75);
            await new Promise(r => setTimeout(r, 15000));

            // Parse File
            const files = fs.readdirSync(downloadPath).filter(f => !f.endsWith('.tmp') && !f.endsWith('.crdownload'));
            if (files.length > 0) {
                const workbook = xlsx.readFile(path.join(downloadPath, files[0]));
                const rows = xlsx.utils.sheet_to_json(workbook.Sheets[workbook.SheetNames[0]], { header: 1 });
                // Parsing logic...
                // (Simplified Mapper):
                let cSku = -1, cQty = -1;
                rows.forEach((r, i) => {
                    r.forEach((c, j) => {
                        const s = String(c).toUpperCase();
                        if (s.includes('CODE') || (s.includes('ITEM') && s.includes('NO'))) cSku = j;
                        if (s.includes('QTY') || s.includes('QUANTITY')) cQty = j;
                    });
                });
                if (cSku > -1) {
                    rows.forEach((r, i) => {
                        if (i > 3 && r[cSku]) {
                            const q = cQty > -1 ? String(r[cQty] || 0).replace(/,/g, '') : '0';
                            const n = r[cSku + 1] || r[cSku + 2] || '';
                            data.push({ sku: String(r[cSku]), name: String(n), warehouse: warehouse || '', quantity: q });
                        }
                    });
                }
                progress(`Đã đọc ${data.length} mã vật tư từ Excel`, 0.85);
            }
        } else {
            progress('Không tìm thấy nút Export. Chuyển sang cào dữ liệu HTML...', 0.7);

            // HTML SCRAPING LOGIC
            const htmlItems = await page.evaluate(() => {
                const results = [];
                // Crystal usually uses nested tables. We want the one with data.
                const tables = document.querySelectorAll('table');
                tables.forEach(tbl => {
                    if (tbl.rows.length < 5) return;
                    for (let i = 0; i < tbl.rows.length; i++) {
                        const row = tbl.rows[i];
                        const cells = [];
                        for (let c of row.cells) cells.push(c.innerText.trim());

                        // Heuristic to find SKU and Qty
                        let sku = '';
                        let qty = '';
                        let name = '';

                        // We expect SKU to be alphanumeric, Qty numeric
                        // and they should be on the same row.

                        // Filter out headers
                        if (cells.some(c => c.includes('Page') || c.includes('Date') || c.includes('Total'))) continue;

                        // Identify SKU: > 3 chars, alphanumeric
                        // Identify Qty: Numeric, maybe commas

                        cells.forEach(c => {
                            if (!sku && /^[A-Z0-9.\-]+$/.test(c) && c.length > 3) sku = c;
                            else if (sku && !name && c.length > 5 && !/^[0-9,.]+$/.test(c)) name = c;
                            else if (sku && /^[0-9,.]+$/.test(c) && c.length < 10) qty = c;
                        });

                        if (sku && qty) {
                            results.push({ sku, name, quantity: qty });
                        }
                    }
                });
                return results;
            });

            if (htmlItems.length > 0) {
                progress(`Đã cào ${htmlItems.length} dòng từ HTML`, 0.85);
                htmlItems.forEach(i => {
                    data.push({
                        sku: i.sku,
                        name: i.name,
                        warehouse: warehouse || '',
                        quantity: i.quantity.replace(/,/g, '')
                    });
                });
            } else {
                progress('HTML Scraping không tìm thấy dữ liệu.', 0.8);
            }
        }

        await browser.close();

        if (data.length > 0) {
            progress('Đang lưu dữ liệu vào cơ sở dữ liệu...', 0.95);
            // Save to DB
            withTransaction(db, async () => {
                // KHÔNG xóa sạch dữ liệu cũ nữa để bảo toàn số KK
                // Chúng ta sẽ set quantity = 0 cho các mã không xuất hiện trong lượt sync này

                const stmt = db.prepare(`
                    INSERT INTO erp_stock (sku, sku_plain, name, warehouse, quantity, updatedAt) 
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(sku, warehouse) DO UPDATE SET
                        quantity = excluded.quantity,
                        name = excluded.name,
                        updatedAt = excluded.updatedAt,
                        sku_plain = excluded.sku_plain,
                        difference = CAST(COALESCE(total_kk, 0) AS REAL) - CAST(REPLACE(excluded.quantity, ',', '') AS REAL)
                `);

                for (const item of data) {
                    await new Promise((resolve, reject) => {
                        stmt.run(item.sku, normalizeSku(item.sku), item.name, item.warehouse, item.quantity, syncMarker, (err) => {
                            if (err) reject(err); else resolve();
                        });
                    });
                }

                await new Promise((resolve, reject) => {
                    stmt.finalize((err) => {
                        if (err) reject(err); else resolve();
                    });
                });

                // Cập nhật các mã KHÔNG có trong lần sync này thành Qty = 0
                // Chỉ áp dụng cho kho đang sync (nếu có chọn kho)
                let clearQuery = `UPDATE erp_stock SET quantity = '0', updatedAt = ?, 
                                 difference = CAST(COALESCE(total_kk, 0) AS REAL)
                                 WHERE updatedAt < ?`;
                let clearParams = [syncMarker, syncMarker];
                if (warehouse) {
                    clearQuery += ` AND warehouse = ?`;
                    clearParams.push(warehouse);
                }

                await new Promise((resolve, reject) => {
                    db.run(clearQuery, clearParams, (err) => {
                        if (err) reject(err); else resolve();
                    });
                });

            }).then(() => {
                progress('Hoàn tất đồng bộ!', 1.0);
                res.json({ message: 'Sync successful', count: data.length });
                io.emit('erp_update_all', {});
            }).catch(err => {
                console.error('[ERP Sync] Transition error:', err);
                res.status(500).json({ error: 'Sync failed: ' + err.message });
            });
        } else {
            progress('Lỗi: Không lấy được dữ liệu!', 1.0);
            res.status(500).json({ error: 'Không lấy được dữ liệu (Excel & HTML đều thất bại).' });
        }

    } catch (err) {
        console.error('[ERP] Lỗi:', err);
        if (browser) await browser.close();
        res.status(500).json({ error: 'Lỗi: ' + err.message });
    } finally {
        // Cleanup...
        setTimeout(() => {
            try {
                if (fs.existsSync(downloadPath)) fs.rmdirSync(downloadPath, { recursive: true });
                if (userDataDir && fs.existsSync(userDataDir)) fs.rm(userDataDir, { recursive: true, force: true }, () => { });
            } catch (e) { }
        }, 5000);
    }
});

// Duplicate audit-update removed (the one at line 1355 was replaced by the more robust one at line 1592)

app.get('/api/erp/stock/:sku/all', (req, res) => {
    const sku = req.params.sku;
    const sku_plain = normalizeSku(sku);
    let query = `SELECT * FROM erp_stock WHERE (sku = ? OR sku_plain = ?)`;
    let params = [sku, sku_plain];
    if (warehouse) {
        query += ` AND warehouse = ?`;
        params.push(warehouse);
    }

    db.get(query, params, (err, row) => {
        if (err) return res.status(500).json({ error: err.message });
        if (!row) return res.status(404).json({ error: 'Item not found' });
        res.json({ success: true, data: row });
    });
});

app.post('/api/erp/audit-update-slots', (req, res) => {
    const { id, sku, warehouse, slots, auditor } = req.body; // slots: { kk1: val, kk2: val, ... }

    if (!slots) return res.status(400).json({ error: 'Slots are required' });
    if (!id && !sku) return res.status(400).json({ error: 'ID or SKU is required' });

    const processUpdate = (row) => {
        const erpQty = parseFloat((row.quantity || '0').toString().replace(/,/g, '')) || 0;
        let newTotal = 0;
        let updateParts = [];
        let params = [];

        for (let i = 1; i <= 10; i++) {
            const key = `kk${i}`;
            const val = slots[key] !== undefined ? parseFloat(slots[key]) : parseFloat(row[key] || 0);
            newTotal += val;
            updateParts.push(`${key} = ?`);
            params.push(val);
        }

        const diff = newTotal - erpQty;
        updateParts.push(`total_kk = ?`, `difference = ?`);
        params.push(newTotal, diff, row.id);

        db.run(`UPDATE erp_stock SET ${updateParts.join(', ')} WHERE id = ?`, params, function (err) {
            if (err) return res.status(500).json({ error: err.message });

            // Log to history
            db.run(`INSERT INTO logs (username, action, details, timestamp) VALUES (?, ?, ?, ?)`,
                [auditor || 'System', 'UPDATE_ALL_SLOTS', `SKU: ${row.sku}, New Total: ${newTotal}`, new Date().toISOString()]);

            // Notify clients
            io.emit('erp_update', { sku: row.sku, warehouse: row.warehouse });

            res.json({ success: true, total_kk: newTotal, difference: diff });
        });
    };

    if (id) {
        db.get(`SELECT * FROM erp_stock WHERE id = ?`, [id], (err, row) => {
            if (err) return res.status(500).json({ error: err.message });
            if (!row) return res.status(404).json({ error: 'Item not found' });
            processUpdate(row);
        });
    } else {
        // Find by SKU
        let query = 'SELECT * FROM erp_stock WHERE sku = ?';
        let params = [sku];
        if (warehouse) {
            query += ' AND warehouse = ?';
            params.push(warehouse);
        }

        db.get(query, params, (err, row) => {
            if (err) return res.status(500).json({ error: err.message });
            if (row) {
                processUpdate(row);
            } else {
                // INSERT NEW RECORD (Virtual VMS Item case)
                const now = new Date().toISOString();
                // Assume 0 for ERP quantity if not found, since it's likely a VMS-only item or not synced
                // Actually, if it's VMS, we might not know the ERP quantity here unless we fetched it or it was passed.
                // But typically if it's not in erp_stock, ERP Qty is effectively 0 or we rely on what's passed?
                // The frontend 'quantity' passed in might be VMS quantity, but erp_stock.quantity usually refers to ERP system stock.
                // We'll set quantity to 0 for now as it's missing from ERP.
                const erpQty = 0;

                let keys = ['sku', 'warehouse', 'quantity', 'total_kk', 'difference', 'updatedAt'];
                let values = [sku, warehouse || '', '0', 0, 0, now];
                let placeHolders = ['?', '?', '?', '?', '?', '?'];

                let newTotal = 0;
                for (let i = 1; i <= 10; i++) {
                    const key = `kk${i}`;
                    const val = slots[key] !== undefined ? parseFloat(slots[key]) : 0;
                    newTotal += val;
                    keys.push(key);
                    values.push(val);
                    placeHolders.push('?');
                }

                // Recalculate totals for insert
                const diff = newTotal - erpQty;
                // Update specific values in the array
                values[3] = newTotal;
                values[4] = diff;

                const insertSql = `INSERT INTO erp_stock (${keys.join(', ')}) VALUES (${placeHolders.join(', ')})`;

                db.run(insertSql, values, function (insErr) {
                    if (insErr) return res.status(500).json({ error: insErr.message });

                    // Log
                    db.run(`INSERT INTO logs (username, action, details, timestamp) VALUES (?, ?, ?, ?)`,
                        [auditor || 'System', 'CREATE_UPDATE_SLOTS', `SKU: ${sku}, New Total: ${newTotal}`, now]);

                    io.emit('erp_update', { sku: sku, warehouse: warehouse });
                    res.json({ success: true, total_kk: newTotal, difference: diff });
                });
            }
        });
    }
});

app.post('/api/erp/import', upload.single('file'), (req, res) => {
    if (!req.file) return res.status(400).json({ error: 'No file uploaded' });
    const { warehouse } = req.body;

    try {
        const fileBuffer = fs.readFileSync(req.file.path);
        const workbook = xlsx.read(fileBuffer, { type: 'buffer' });
        const sheetName = workbook.SheetNames[0];
        const rows = xlsx.utils.sheet_to_json(workbook.Sheets[sheetName], { header: 1 });

        try {
            fs.unlinkSync(req.file.path);
        } catch (e) { }

        const data = [];
        let cSku = -1, cQty = -1, cName = -1, cWh = -1;

        // Header detection (similar to Sync)
        // Look in first 10 rows
        for (let i = 0; i < Math.min(rows.length, 10); i++) {
            const r = rows[i];
            r.forEach((c, j) => {
                const s = String(c).toUpperCase().trim();
                // Priority specific matches based on user request
                if (s === 'CODE' || s === 'ITEM NO' || s === 'PART NO' || s === 'SKU') cSku = j;
                else if (s.includes('CODE') || s.includes('SKU')) cSku = j; // Fallback

                if (s === 'QTY(PCS)' || s === 'QTY' || s === 'QUANTITY' || s === 'SOLUONG') cQty = j;
                else if (s.includes('QTY') || s.includes('QUANTITY')) cQty = j; // Fallback

                if (s === 'ITEM NAME' || s === 'NAME' || s === 'DESCRIPTION' || s === 'TÊN') cName = j;
                else if (s.includes('NAME') || s.includes('DESC')) cName = j; // Fallback

                if (s.includes('WAREHOUSE') || s.includes('KHO')) cWh = j;
            });
            if (cSku > -1 && cQty > -1) break; // Found headers
        }

        if (cSku === -1) {
            return res.status(400).json({ error: 'Could not detect SKU/Code column in Excel.' });
        }

        rows.forEach((r, i) => {
            // Skip potential header rows if we identified them by content, 
            // but simpler is to just check if the SKU looks valid
            if (i > 0 && r[cSku]) {
                const sku = String(r[cSku]).trim();
                // Basic validation: SKU should be longer than 3 chars roughly
                if (sku.length < 3 || sku.toUpperCase() === 'CODE' || sku.toUpperCase().includes('TOTAL')) return;

                const qtyVal = cQty > -1 ? r[cQty] : '0';
                const q = String(qtyVal || 0).replace(/,/g, '');

                const name = cName > -1 ? (r[cName] || '') : '';
                // If warehouse is not provided in body, try to read from row, else default to 'Unknown'
                const itemWh = warehouse || (cWh > -1 ? (r[cWh] || '') : '');

                if (sku) {
                    data.push({ sku: sku, name: String(name), warehouse: String(itemWh), quantity: q });
                }
            }
        });

        if (data.length > 0) {
            const syncMarker = new Date().toISOString();
            withTransaction(db, async () => {
                // KHÔNG xóa sạch dữ liệu cũ nữa để bảo toàn số KK
                // Chúng ta sẽ set quantity = 0 cho các mã không xuất hiện trong file Excel này

                const stmt = db.prepare(`
                    INSERT INTO erp_stock (sku, sku_plain, name, warehouse, quantity, updatedAt) 
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(sku, warehouse) DO UPDATE SET 
                        quantity = excluded.quantity,
                        name = excluded.name,
                        sku_plain = excluded.sku_plain,
                        updatedAt = excluded.updatedAt,
                        difference = CAST(COALESCE(total_kk, 0) AS REAL) - CAST(REPLACE(excluded.quantity, ',', '') AS REAL)
                `);

                for (const item of data) {
                    await new Promise((resolve, reject) => {
                        stmt.run(item.sku, normalizeSku(item.sku), item.name, item.warehouse, item.quantity, syncMarker, (err) => {
                            if (err) reject(err); else resolve();
                        });
                    });
                }

                await new Promise((resolve, reject) => {
                    stmt.finalize((err) => {
                        if (err) reject(err); else resolve();
                    });
                });

                // Cập nhật các mã KHÔNG có trong file này thành Qty = 0
                // Chỉ áp dụng cho kho đang import (nếu file Excel có chỉ định kho)
                // Hoặc nếu import cho 1 kho cụ thể từ dropdown
                let clearQuery = `UPDATE erp_stock SET quantity = '0', updatedAt = ?,
                                  difference = CAST(COALESCE(total_kk, 0) AS REAL)
                                  WHERE updatedAt < ?`;
                let clearParams = [syncMarker, syncMarker];

                // Nếu User chọn kho từ Dropdown (warehouse variable)
                if (warehouse && warehouse !== 'Tất cả') {
                    clearQuery += ` AND warehouse = ?`;
                    clearParams.push(warehouse);
                }

                await new Promise((resolve, reject) => {
                    db.run(clearQuery, clearParams, (err) => {
                        if (err) reject(err); else resolve();
                    });
                });

            }).then(() => {
                io.emit('erp_update_all', {}); // Thêm dòng này để thông báo cho toàn bộ UI cập nhật
                res.json({ message: 'Import successful', count: data.length });
            }).catch(err => {
                console.error('Import ERP transaction error:', err);
                res.status(500).json({ error: err.message });
            });
        } else {
            res.status(400).json({ error: 'No valid data found in Excel' });
        }

    } catch (e) {
        try {
            if (req.file && fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path);
        } catch (unlinkErr) { }
        console.error('Import ERP error:', e);
        res.status(500).json({ error: e.message });
    }
});

app.post('/api/erp/import-dynamic', upload.single('file'), (req, res) => {
    if (!req.file) return res.status(400).json({ error: 'No file uploaded' });

    try {
        const fileBuffer = fs.readFileSync(req.file.path);
        const workbook = xlsx.read(fileBuffer, { type: 'buffer' });
        const sheetName = workbook.SheetNames[0];
        const rows = xlsx.utils.sheet_to_json(workbook.Sheets[sheetName], { header: 1 });

        try {
            fs.unlinkSync(req.file.path);
        } catch (e) { }

        if (rows.length < 1) return res.status(400).json({ error: 'Excel file is empty' });

        // 1. Identify Headers
        const headers = rows[0].map(h => String(h || '').trim());
        let skuIndex = -1;

        headers.forEach((h, i) => {
            const up = h.toUpperCase();
            if (up === 'CODE' || up === 'SKU' || up === 'MÃ' || up === 'PART NO') skuIndex = i;
        });

        if (skuIndex === -1) {
            return res.status(400).json({ error: 'Could not find "Code" or "SKU" column.' });
        }

        // 2. Identify Dynamic Columns
        const dynamicIndices = [];
        headers.forEach((h, i) => {
            if (i !== skuIndex && h.length > 0) {
                dynamicIndices.push(i);
            }
        });

        if (dynamicIndices.length === 0) {
            return res.json({ message: 'No additional columns found to import.' });
        }

        // 3. Fetch existing SKUs for validation/upsert
        db.all("SELECT sku FROM erp_stock", [], (err, stockRows) => {
            if (err) return res.status(500).json({ error: err.message });

            const validSkus = new Set(stockRows.map(r => String(r.sku).trim().toUpperCase()));
            const updates = [];
            const inserts = [];

            const now = new Date().toISOString();

            // Process rows
            for (let i = 1; i < rows.length; i++) {
                const row = rows[i];
                const originalSku = row[skuIndex]?.toString().trim();
                const skuUpper = originalSku?.toUpperCase();

                if (!originalSku) continue;

                const rowData = {};
                dynamicIndices.forEach(idx => {
                    const key = headers[idx];
                    const val = row[idx];
                    if (val !== undefined && val !== null && String(val).trim() !== '') {
                        rowData[key] = val;
                    }
                });

                if (Object.keys(rowData).length > 0) {
                    if (validSkus.has(skuUpper)) {
                        updates.push({ sku: originalSku, data: rowData });
                    } else {
                        inserts.push({ sku: originalSku, data: rowData });
                    }
                }
            }

            if (updates.length > 0 || inserts.length > 0) {
                withTransaction(db, async () => {
                    // Handle Updates
                    const updateStmt = db.prepare(`
                        UPDATE erp_stock 
                        SET custom_data = json_patch(COALESCE(custom_data, '{}'), ?) 
                        WHERE sku = ? COLLATE NOCASE
                    `);

                    for (const u of updates) {
                        await new Promise((resolve, reject) => {
                            updateStmt.run(JSON.stringify(u.data), u.sku, (err) => {
                                if (err) reject(err); else resolve();
                            });
                        });
                    }
                    await new Promise((resolve, reject) => updateStmt.finalize((err) => { if (err) reject(err); else resolve(); }));

                    // Handle Inserts (New VMS Items)
                    const insertStmt = db.prepare(`
                        INSERT INTO erp_stock (sku, sku_plain, warehouse, quantity, total_kk, difference, custom_data, updatedAt)
                        VALUES (?, ?, '', '0', 0, 0, ?, ?)
                    `);

                    for (const ins of inserts) {
                        await new Promise((resolve, reject) => {
                            insertStmt.run(ins.sku, normalizeSku(ins.sku), JSON.stringify(ins.data), now, (err) => {
                                if (err) reject(err); else resolve();
                            });
                        });
                    }

                    await new Promise((resolve, reject) => insertStmt.finalize((err) => { if (err) reject(err); else resolve(); }));

                }).then(() => {
                    io.emit('erp_update_all', {});
                    if (!res.headersSent) {
                        res.json({
                            successCount: updates.length + inserts.length,
                            updates: updates.length,
                            inserts: inserts.length,
                            failCount: 0,
                            failedDetails: []
                        });
                    }
                }).catch(err => {
                    console.error('Import Dynamic transaction error:', err);
                    if (!res.headersSent) {
                        res.status(500).json({ error: err.message });
                    }
                });
            } else {
                if (!res.headersSent) {
                    res.json({
                        successCount: 0,
                        failCount: 0,
                        failedDetails: []
                    });
                }
            }
        });

    } catch (e) {
        try {
            if (req.file && fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path);
        } catch (unlinkErr) { }
        console.error('Import Dynamic error:', e);
        res.status(500).json({ error: e.message });
    }
});


app.post('/api/erp/update-packing', (req, res) => {
    const { sku, warehouse, note } = req.body;
    if (!sku) return res.status(400).json({ error: 'SKU is required' });

    const sku_plain = normalizeSku(sku);
    let query = `UPDATE erp_stock SET packing_diff = ? WHERE (sku = ? OR sku_plain = ?)`;
    let params = [note, sku, sku_plain];

    if (warehouse) {
        query += ` AND warehouse = ?`;
        params.push(warehouse);
    }

    db.run(query, params, function (err) {
        if (err) return res.status(500).json({ error: err.message });
        if (this.changes === 0) {
            // Upsert: Item not found, insert new record
            const insertQuery = `INSERT INTO erp_stock (sku, sku_plain, warehouse, packing_diff, quantity, total_kk, difference, updatedAt) 
                                 VALUES (?, ?, ?, ?, '0', 0, 0, ?)`;
            const now = new Date().toISOString();
            db.run(insertQuery, [sku, sku_plain, warehouse || '', note, now], function (insErr) {
                if (insErr) return res.status(500).json({ error: insErr.message });
                io.emit('erp_update', { sku: sku, warehouse: warehouse });
                res.json({ success: true, changes: 1, action: 'insert' });
            });
        } else {
            io.emit('erp_update', { sku: sku, warehouse: warehouse });
            res.json({ success: true, changes: this.changes, action: 'update' });
        }
    });
});


app.post('/api/erp/update-diff-nn', (req, res) => {
    const { sku, diffNn, warehouse, mergedSkus } = req.body;
    if (!sku) return res.status(400).json({ error: 'SKU is required' });

    const newMergeList = mergedSkus || [sku];
    const newMergeJson = JSON.stringify(newMergeList);
    const value = diffNn || '0';
    const now = new Date().toISOString();

    const safeNewMergeList = Array.isArray(newMergeList) ? newMergeList : [sku];

    // 0. Helper to ensure items exist (Upsert logic)
    const ensureItemsExist = () => {
        return new Promise((resolve, reject) => {
            if (safeNewMergeList.length === 0) return resolve();

            // Simple approach: try insert for each. 
            // Since we don't have batch insert that ignores efficiently easily in this setup without constructing huge query.
            let pending = safeNewMergeList.length;
            let hasError = false;

            safeNewMergeList.forEach(s => {
                db.run(
                    "INSERT OR IGNORE INTO erp_stock (sku, sku_plain, warehouse, quantity, total_kk, difference, updatedAt) VALUES (?, ?, '', '0', 0, 0, ?)",
                    [s, normalizeSku(s), now],
                    (err) => {

                        if (err && !hasError) { hasError = true; reject(err); }
                        pending--;
                        if (pending <= 0 && !hasError) resolve();
                    }
                );
            });
        });
    };

    ensureItemsExist().then(() => {
        // 1. Get previous state to handle removals
        db.get('SELECT merged_skus FROM erp_stock WHERE sku = ?', [sku], (err, row) => {
            if (err) return res.status(500).json({ error: err.message });

            let oldSkus = [];
            if (row && row.merged_skus) {
                try {
                    const parsed = JSON.parse(row.merged_skus);
                    if (Array.isArray(parsed)) oldSkus = parsed;
                } catch (e) { }
            }

            // 2. Identify all SKUs that need updating (old ones and new ones)
            const allContextSkus = [...new Set([...oldSkus, ...safeNewMergeList])];
            if (allContextSkus.length === 0) return res.json({ success: true });

            // 3. Clear old and Set new
            const placeholders = allContextSkus.map(() => '?').join(',');
            const clearQuery = `UPDATE erp_stock SET diff_nn = NULL, merged_skus = NULL WHERE sku IN (${placeholders})`;

            db.run(clearQuery, allContextSkus, (err) => {
                if (err) return res.status(500).json({ error: err.message });

                const newPlaceholders = safeNewMergeList.map(() => '?').join(',');
                const updateQuery = `UPDATE erp_stock SET diff_nn = ?, merged_skus = ? WHERE sku IN (${newPlaceholders})`;

                db.run(updateQuery, [value, newMergeJson, ...safeNewMergeList], (err2) => {
                    if (err2) return res.status(500).json({ error: err2.message });
                    io.emit('erp_update_all', {}); // Emit update all to force refresh
                    res.json({ success: true });
                });
            });
        });
    }).catch(err => {
        res.status(500).json({ error: err.message });
    });
});

// Update stock audit - saves to both erp_stock and stock_audit tables
app.post('/api/erp/audit-update', (req, res) => {
    const { sku, quantity, warehouse, auditor, packagingStandard, horRows, verRows, evenRows, oddRows, individualBags } = req.body;

    if (!sku || quantity === undefined) {
        return res.status(400).json({ error: 'SKU and quantity are required' });
    }

    const now = new Date().toISOString();

    // Helper to insert into history
    const insertHistory = (sku, warehouse, quantity, targetCol, totalKk, difference, auditor, packagingStandard, horRows, verRows, evenRows, oddRows, individualBags, resCallback) => {
        const insertQuery = `INSERT INTO stock_audit (sku, warehouse, packagingStandard, horRows, verRows, evenRows, oddRows, individualBags, totalResult, auditor, timestamp) 
                             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;
        db.run(insertQuery, [
            sku,
            warehouse || '',
            packagingStandard || 0,
            horRows || 0,
            verRows || 0,
            evenRows || 0,
            oddRows || 0,
            individualBags || 0,
            quantity,
            auditor || 'Unknown',
            new Date().toISOString()
        ], function (insertErr) {
            if (insertErr) {
                console.error('[POST /api/erp/audit-update] Insert history error:', insertErr.message);
            }
            console.log(`[POST /api/erp/audit-update] Processed ${sku} into ${targetCol} with quantity ${quantity}`);
            resCallback({
                success: true,
                targetCol,
                totalKk,
                difference,
                historyRecorded: !insertErr
            });
        });
    };

    // 1. Try to find the existing row by SKU first
    let query = 'SELECT * FROM erp_stock WHERE sku = ?';
    let params = [sku];

    // If warehouse is explicitly provided (and not empty), strict filter
    if (warehouse && warehouse.trim() !== '') {
        query += ' AND warehouse = ?';
        params.push(warehouse);
    }

    db.get(query, params, (err, row) => {
        if (err) {
            console.error('[POST /api/erp/audit-update] Error:', err.message);
            return res.status(500).json({ error: err.message });
        }

        const effectiveWarehouse = row ? row.warehouse : (warehouse || '');

        // Define Update Logic
        const performUpdate = (targetRow) => {
            // Find next available kk slot (kk1 to kk10)
            let targetCol = null;
            for (let i = 1; i <= 10; i++) {
                const colName = `kk${i}`;
                // LOOSE CHECK: Treat 0 ('0' or 0) as empty because DB defaults to '0'.
                const val = targetRow[colName];
                if (val === null || val === undefined || val === '' || val == 0 || val == '0') {
                    targetCol = colName;
                    break;
                }
            }

            if (!targetCol) {
                return res.status(400).json({ error: 'All audit slots (kk1-kk10) are full. Slots 1-10 have data.' });
            }

            // Calculate totals
            const kkValues = [];
            for (let i = 1; i <= 10; i++) {
                const colName = `kk${i}`;
                if (colName === targetCol) {
                    kkValues.push(parseFloat(quantity) || 0);
                } else {
                    // Use existing value
                    const exVal = targetRow[colName];
                    if (exVal !== null && exVal !== undefined && exVal !== '') {
                        kkValues.push(parseFloat(exVal));
                    } else {
                        kkValues.push(0);
                    }
                }
            }
            const totalKk = kkValues.reduce((sum, val) => sum + val, 0);
            const erpQty = parseFloat((targetRow.quantity || '0').toString().replace(/,/g, '')) || 0;
            const difference = totalKk - erpQty;

            // Update erp_stock using ID to be precise
            const updateQuery = `UPDATE erp_stock SET ${targetCol} = ?, total_kk = ?, difference = ?, updatedAt = ? WHERE id = ?`;

            db.run(updateQuery, [quantity, totalKk, difference, now, targetRow.id], function (updateErr) {
                if (updateErr) {
                    console.error('[POST /api/erp/audit-update] Update error:', updateErr.message);
                    return res.status(500).json({ error: updateErr.message });
                }
                insertHistory(sku, targetRow.warehouse, quantity, targetCol, totalKk, difference, auditor, packagingStandard, horRows, verRows, evenRows, oddRows, individualBags, (response) => {
                    io.emit('erp_update', { sku, warehouse: targetRow.warehouse });
                    res.json(response);
                });
            });
        };

        if (!row) {
            // SKU not found - Insert new record into erp_stock
            console.log(`[POST /api/erp/audit-update] SKU ${sku} not found, creating new entry in erp_stock...`);

            const newTotal = parseFloat(quantity);
            const diff = newTotal - 0;

            const createQuery = `INSERT INTO erp_stock (sku, warehouse, quantity, kk1, total_kk, difference, updatedAt) 
                                     VALUES (?, ?, '0', ?, ?, ?, ?)`;

            db.run(createQuery, [sku, effectiveWarehouse, quantity, diff, diff, now], function (createErr) {
                if (createErr) {
                    // Check for UNIQUE constraint failure (Race Condition)
                    if (createErr.code === 'SQLITE_CONSTRAINT' || createErr.message.includes('UNIQUE constraint failed')) {
                        console.warn(`[POST /api/erp/audit-update] Race condition detected for SKU ${sku}. Retrying as UPDATE...`);
                        // Retry finding the row that was just inserted by someone else
                        // We must find by SKU and Warehouse to be specific
                        db.get('SELECT * FROM erp_stock WHERE sku = ? AND warehouse = ?', [sku, effectiveWarehouse], (retryErr, retryRow) => {
                            if (retryErr) {
                                return res.status(500).json({ error: retryErr.message });
                            }
                            if (retryRow) {
                                performUpdate(retryRow);
                            } else {
                                // Should not happen if constraint failed
                                return res.status(500).json({ error: 'Failed to insert and failed to find existing row.' });
                            }
                        });
                        return;
                    }

                    console.error('[POST /api/erp/audit-update] Create error:', createErr.message);
                    return res.status(500).json({ error: createErr.message });
                }
                insertHistory(sku, effectiveWarehouse, quantity, 'kk1', newTotal, diff, auditor, packagingStandard, horRows, verRows, evenRows, oddRows, individualBags, (response) => {
                    io.emit('erp_update', { sku, warehouse: effectiveWarehouse });
                    res.json(response);
                });
            });
        } else {
            // Update existing record
            performUpdate(row);
        }
    });
});

// Get audit history with optional filters
app.get('/api/audit/history', (req, res) => {
    console.log('[GET /api/audit/history] Request received with filters:', req.query);
    const { auditor, sku } = req.query;
    let query = 'SELECT * FROM stock_audit WHERE 1=1';
    const params = [];

    if (auditor) {
        query += ' AND auditor = ?';
        params.push(auditor);
    }

    if (sku) {
        query += ' AND sku LIKE ?';
        params.push(`%${sku}%`);
    }

    query += ' ORDER BY timestamp DESC';

    db.all(query, params, (err, rows) => {
        if (err) {
            console.error('[GET /api/audit/history] Database error:', err.message);
            return res.status(500).json({ error: err.message });
        }
        console.log(`[GET /api/audit/history] Returning ${rows.length} records`);
        res.json(rows);
    });
});


/**
 * Helper to resync ERP stock after audit change (delete/edit)
 * Recalculates all KK slots and totals from history
 */
function syncStockAfterAuditChange(sku, warehouse) {
    if (!sku) return;
    const effectiveWarehouse = warehouse || '';

    // 1. Fetch all audit history for this item
    db.all(
        'SELECT totalResult FROM stock_audit WHERE sku = ? AND warehouse = ? ORDER BY id ASC',
        [sku, effectiveWarehouse],
        (err, rows) => {
            if (err) return console.error('Sync Stock Error (Fetch):', err);

            // 2. Prepare new KK values
            let kkValues = Array(10).fill('0');
            let totalKk = 0;

            rows.forEach((row, index) => {
                if (index < 10) {
                    kkValues[index] = row.totalResult.toString();
                }
                totalKk += parseFloat(row.totalResult) || 0;
            });

            // 3. Update ERP Stock record
            db.get(
                'SELECT quantity FROM erp_stock WHERE sku = ? AND warehouse = ?',
                [sku, effectiveWarehouse],
                (err, erpRow) => {
                    if (err) return console.error('Sync Stock Error (Get ERP):', err);

                    const erpQty = parseFloat((erpRow?.quantity || '0').toString().replace(/,/g, '')) || 0;
                    const diff = totalKk - erpQty;

                    const query = `
                        UPDATE erp_stock SET 
                        kk1 = ?, kk2 = ?, kk3 = ?, kk4 = ?, kk5 = ?, 
                        kk6 = ?, kk7 = ?, kk8 = ?, kk9 = ?, kk10 = ?, 
                        total_kk = ?, difference = ?, updatedAt = ?,
                        version = version + 1
                        WHERE sku = ? AND warehouse = ?
                    `;

                    const params = [
                        ...kkValues, totalKk, diff,
                        new Date().toISOString(),
                        sku, effectiveWarehouse
                    ];

                    db.run(query, params, (updErr) => {
                        if (updErr) console.error('Sync Stock Error (Update):', updErr);
                        else io.emit('erp_update', { sku, warehouse: effectiveWarehouse });
                    });
                }
            );
        }
    );
}

// Update audit record
app.put('/api/audit/history/:id', (req, res) => {
    const { id } = req.params;
    const { sku, warehouse, packagingStandard, horRows, verRows, evenRows, oddRows, individualBags, totalResult } = req.body;

    const query = `UPDATE stock_audit SET 
        sku = ?, warehouse = ?, packagingStandard = ?, horRows = ?, verRows = ?, 
        evenRows = ?, oddRows = ?, individualBags = ?, totalResult = ?
        WHERE id = ?`;

    const params = [sku, warehouse, packagingStandard, horRows, verRows, evenRows, oddRows, individualBags, totalResult, id];

    db.run(query, params, function (err) {
        if (err) return res.status(500).json({ error: err.message });
        if (this.changes === 0) return res.status(404).json({ error: 'Record not found' });

        // Sync after edit
        syncStockAfterAuditChange(sku, warehouse);
        res.json({ success: true, changes: this.changes });
    });
});

// Delete single audit record
app.delete('/api/audit/history/:id', (req, res) => {
    const { id } = req.params;

    // Get info before delete to sync later
    db.get('SELECT sku, warehouse FROM stock_audit WHERE id = ?', [id], (err, row) => {
        if (err) return res.status(500).json({ error: err.message });
        if (!row) return res.status(404).json({ error: 'Record not found' });

        db.run('DELETE FROM stock_audit WHERE id = ?', [id], function (delErr) {
            if (delErr) return res.status(500).json({ error: delErr.message });

            // Trigger Sync
            syncStockAfterAuditChange(row.sku, row.warehouse);

            res.json({ success: true, deleted: this.changes });
        });
    });
});

// Update stock audit item (User Edit) and sync
app.put('/api/stock-audit/:id', (req, res) => {
    const { id } = req.params;
    const { totalResult, note } = req.body;

    db.get('SELECT sku, warehouse FROM stock_audit WHERE id = ?', [id], (err, row) => {
        if (err) return res.status(500).json({ error: err.message });
        if (!row) return res.status(404).json({ error: 'Record not found' });

        db.run('UPDATE stock_audit SET totalResult = ?, note = ? WHERE id = ?', [totalResult, note, id], function (updateErr) {
            if (updateErr) return res.status(500).json({ error: updateErr.message });

            // Trigger Sync
            syncStockAfterAuditChange(row.sku, row.warehouse);

            res.json({ success: true, changes: this.changes });
        });
    });
});

// Delete multiple audit records
app.post('/api/audit/history/delete-multiple', (req, res) => {
    const { ids } = req.body;
    if (!ids || !Array.isArray(ids) || ids.length === 0) {
        return res.status(400).json({ error: 'IDs array is required' });
    }

    const placeholders = ids.map(() => '?').join(',');

    // Get distinct items to sync
    db.all(`SELECT DISTINCT sku, warehouse FROM stock_audit WHERE id IN (${placeholders})`, ids, (err, rowsToSync) => {
        if (err) return res.status(500).json({ error: err.message });

        db.run(`DELETE FROM stock_audit WHERE id IN (${placeholders})`, ids, function (delErr) {
            if (delErr) return res.status(500).json({ error: delErr.message });

            // Trigger Sync for each affected item
            rowsToSync.forEach(row => {
                syncStockAfterAuditChange(row.sku, row.warehouse);
            });

            res.json({ success: true, deleted: this.changes });
        });
    });
});

// Delete all audit records
app.delete('/api/audit/history/all', (req, res) => {
    db.run('DELETE FROM stock_audit', function (err) {
        if (err) return res.status(500).json({ error: err.message });

        // Reset all ERP values to 0
        // Calculate difference as (0 - Quantity)
        // SQLite: REPLACE(quantity, ',', '') might need to be careful with nulls
        const resetQuery = `
            UPDATE erp_stock SET 
            kk1='0', kk2='0', kk3='0', kk4='0', kk5='0', 
            kk6='0', kk7='0', kk8='0', kk9='0', kk10='0', 
            total_kk = 0,
            difference = 0 - CAST(REPLACE(COALESCE(quantity, '0'), ',', '') AS NUMERIC),
            updatedAt = ?
        `;

        db.run(resetQuery, [new Date().toISOString()], (resetErr) => {
            if (resetErr) console.error('Reset ERP Error:', resetErr);
            io.emit('erp_update_all', {}); // New event for full refresh
            res.json({ success: true, deleted: this.changes });
        });
    });
});

app.post('/api/notify', (req, res) => {
    const { message, type, metadata } = req.body;
    if (!message) return res.status(400).json({ error: 'Message required' });

    const time = new Date().toISOString();
    const metaStr = JSON.stringify(metadata || {});

    db.run('INSERT INTO notifications (type, message, time, metadata) VALUES (?, ?, ?, ?)',
        [type || 'INFO', message, time, metaStr],
        function (err) {
            if (err) return res.status(500).json({ error: err.message });

            const notif = {
                id: this.lastID,
                type: type || 'INFO',
                message,
                time,
                metadata: metadata || {},
                readBy: []
            };

            io.emit('notification', notif);
            console.log(`[Admin Notify] Broadcasted: ${message}`);
            res.json({ success: true, data: notif });
        }
    );
});

// Notifications APIs
app.get('/api/notifications', (req, res) => {
    const { user } = req.query;
    db.all('SELECT * FROM notifications ORDER BY id DESC LIMIT 100', [], (err, rows) => {
        if (err) return res.status(500).json({ error: err.message });

        const filtered = rows.filter(r => {
            const hidden = JSON.parse(r.hiddenBy || '[]');
            if (user && hidden.includes(user)) return false;

            // Exclusive Claim Filter for WARNING
            if (r.type === 'WARNING') {
                const readers = JSON.parse(r.readBy || '[]');
                if (readers.length > 0 && user && !readers.includes(user)) return false;
            }
            return true;
        });

        const parsed = filtered.map(r => ({
            ...r,
            readBy: JSON.parse(r.readBy || '[]'),
            metadata: JSON.parse(r.metadata || '{}'),
            hiddenBy: JSON.parse(r.hiddenBy || '[]')
        }));
        res.json(parsed);
    });
});

app.post('/api/notifications/:id/read', (req, res) => {
    const { id } = req.params;
    const { user } = req.body;
    if (!user) return res.status(400).json({ error: 'User required' });

    db.get('SELECT * FROM notifications WHERE id = ?', [id], (err, row) => {
        if (err || !row) return res.status(404).json({ error: 'Not found' });

        let readers = JSON.parse(row.readBy || '[]');

        // Exclusive CLaim Logic for WARNING
        if (row.type === 'WARNING' && readers.length > 0 && !readers.includes(user)) {
            return res.status(403).json({ success: false, message: `Đã được nhận bởi ${readers[0]}` });
        }

        if (!readers.includes(user)) readers.push(user);

        db.run('UPDATE notifications SET readBy = ? WHERE id = ?', [JSON.stringify(readers), id], (err) => {
            if (err) return res.status(500).json({ error: err.message });

            io.emit('notification_update', {
                id: parseInt(id),
                readBy: readers,
                type: row.type,
                claimedBy: readers[0]
            });
            res.json({ success: true, readBy: readers });
        });
    });
});

app.post('/api/notifications/:id/resolve', (req, res) => {
    const { id } = req.params;
    const { user, resultText } = req.body;
    if (!user) return res.status(400).json({ error: 'User required' });

    db.get('SELECT * FROM notifications WHERE id = ?', [id], (err, row) => {
        if (err || !row) return res.status(404).json({ error: 'Not found' });

        let meta = JSON.parse(row.metadata || '{}');
        meta.resolutionResult = resultText || 'Đã kiểm lại';

        db.run('UPDATE notifications SET type = ?, metadata = ? WHERE id = ?', ['RESOLVED', JSON.stringify(meta), id], (err) => {
            if (err) return res.status(500).json({ error: err.message });

            io.emit('notification_update', {
                id: parseInt(id),
                type: 'RESOLVED',
                message: row.message,
                metadata: meta
            });
            res.json({ success: true });
        });
    });
});

app.post('/api/notifications/hide', (req, res) => {
    const { ids, user } = req.body;
    if (!ids || !user) return res.status(400).json({ error: 'Invalid data' });

    db.get('SELECT role FROM users WHERE username = ?', [user], (err, uRow) => {
        if (err || !uRow) return res.status(404).json({ error: 'User not found' });

        if (uRow.role === 'admin') {
            // Global Delete for Admin
            const placeholders = ids.map(() => '?').join(',');
            db.run(`DELETE FROM notifications WHERE id IN (${placeholders})`, ids, function (err) {
                if (err) return res.status(500).json({ error: err.message });
                io.emit('notifications_deleted', { ids: ids });
                res.json({ success: true, deleted: this.changes });
            });
        } else {
            // Local Hide for User
            let processed = 0;
            ids.forEach(id => {
                db.get('SELECT hiddenBy FROM notifications WHERE id = ?', [id], (err, nRow) => {
                    if (nRow) {
                        let hidden = JSON.parse(nRow.hiddenBy || '[]');
                        if (!hidden.includes(user)) {
                            hidden.push(user);
                            db.run('UPDATE notifications SET hiddenBy = ? WHERE id = ?', [JSON.stringify(hidden), id]);
                        }
                    }
                    processed++;
                    if (processed === ids.length) {
                        res.json({ success: true });
                    }
                });
            });
        }
    });
});

// Catch-all route for Flutter SPA (Single Page Application)
// This must be the LAST route defined to avoid overriding API routes
app.get('*', (req, res) => {
    const flutterIndex = path.join(__dirname, 'public_flutter', 'index.html');
    if (fs.existsSync(flutterIndex)) {
        res.sendFile(flutterIndex);
    } else {
        // If not an API route and index.html doesn't exist, return 404
        if (!req.path.startsWith('/api/')) {
            res.status(404).send('Page not found. If this is a new deployment, please ensure build artifacts are correctly placed.');
        } else {
            res.status(404).json({ error: 'API route not found' });
        }
    }
});

// Socket.io connection
io.on('connection', (socket) => {
    console.log('Client connected to socket');
});

// Keep-alive mechanism for Render Free Tier (Self-Ping)
const keepAliveUrl = 'https://inventor-server.onrender.com';
if (process.env.NODE_ENV === 'production') {
    console.log(`[Keep-Alive] Self-ping initialized for: ${keepAliveUrl}`);
    setInterval(() => {
        https.get(keepAliveUrl, (res) => {
            console.log(`[Keep-Alive] Ping successful: ${res.statusCode}`);
        }).on('error', (err) => {
            console.error('[Keep-Alive] Ping failed:', err.message);
        });
    }, 14 * 60 * 1000); // 14 minutes (Render sleeps after 15)
}

const localIp = getLocalIp();
console.log('-------------------------------------------');
console.log(`🚀 Server đang sẵn sàng:`);
console.log(`- Web HTTP:  http://${localIp}:3000`);
if (sslOptions) {
    console.log(`- Web HTTPS: https://${localIp}:3443`);
}
console.log('-------------------------------------------');


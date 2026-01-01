const { createClient } = require('@libsql/client');

// Kết nối Turso
const turso = createClient({
    url: process.env.TURSO_DATABASE_URL || 'file:local.db',
    authToken: process.env.TURSO_AUTH_TOKEN,
});

/**
 * Wrapper to make Turso (libSQL) compatible with sqlite3 callback-style API
 */
class TursoWrapper {
    constructor(client) {
        this.client = client;
        this.currentTransaction = null; // Initialize transaction state
    }

    async run(sql, ...args) {
        let callback = null;
        let params = [];

        if (args.length > 0 && typeof args[args.length - 1] === 'function') {
            callback = args.pop();
        }

        if (args.length === 1 && Array.isArray(args[0])) {
            params = args[0];
        } else {
            params = args;
        }

        const sqlUpper = sql.trim().toUpperCase();

        // Handle Transactions
        if (sqlUpper.startsWith('BEGIN')) {
            try {
                if (this.currentTransaction) {
                    console.warn('[Turso] Transaction already in progress, nested BEGIN ignored.');
                } else {
                    this.currentTransaction = await this.client.transaction();
                }
                if (callback) callback.call({ changes: 0 }, null);
                return { changes: 0 };
            } catch (error) {
                console.error('Turso BEGIN error:', error);
                if (callback) callback(error);
                throw error;
            }
        }

        if (sqlUpper.startsWith('COMMIT')) {
            try {
                if (this.currentTransaction) {
                    await this.currentTransaction.commit();
                    this.currentTransaction = null;
                }
                if (callback) callback.call({ changes: 0 }, null);
                return { changes: 0 };
            } catch (error) {
                console.error('Turso COMMIT error:', error);
                if (callback) callback(error);
                throw error;
            }
        }

        if (sqlUpper.startsWith('ROLLBACK')) {
            try {
                if (this.currentTransaction) {
                    await this.currentTransaction.rollback();
                    this.currentTransaction = null;
                }
                if (callback) callback.call({ changes: 0 }, null);
                return { changes: 0 };
            } catch (error) {
                // Rollback might fail if already failed, ignore
                this.currentTransaction = null;
                if (callback) callback(null);
                return { changes: 0 };
            }
        }

        const executor = this.currentTransaction || this.client;

        try {
            const result = await executor.execute({
                sql: sql,
                args: params || [],
            });
            const info = {
                changes: result.rowsAffected,
                lastID: result.lastInsertRowid ? Number(result.lastInsertRowid) : null
            };
            if (callback) callback.call(info, null);
            return info;
        } catch (error) {
            const errStr = String(error).toLowerCase();
            const isMigrationError = errStr.includes('duplicate column name') ||
                errStr.includes('already exists') ||
                errStr.includes('duplicate column') ||
                errStr.includes('sku_plain');

            if (isMigrationError) {
                console.warn(`[Turso Migration Note] ${error.message} (Safe to ignore)`);
                if (callback) callback(null);
                return { changes: 0, lastID: null };
            }

            console.error('Turso run error:', error);
            if (callback) {
                callback(error);
                return null;
            }
            throw error;
        }
    }

    async get(sql, ...args) {
        let callback = null;
        let params = [];

        if (args.length > 0 && typeof args[args.length - 1] === 'function') {
            callback = args.pop();
        }

        if (args.length === 1 && Array.isArray(args[0])) {
            params = args[0];
        } else {
            params = args;
        }

        const executor = this.currentTransaction || this.client;

        try {
            const result = await executor.execute({
                sql: sql,
                args: params || [],
            });
            const row = result.rows[0] ? this._rowToObj(result.rows[0]) : null;
            if (callback) callback(null, row);
            return row;
        } catch (error) {
            console.error('Turso get error:', error);
            if (callback) {
                callback(error);
                return null;
            }
            throw error;
        }
    }

    async all(sql, ...args) {
        let callback = null;
        let params = [];

        if (args.length > 0 && typeof args[args.length - 1] === 'function') {
            callback = args.pop();
        }

        if (args.length === 1 && Array.isArray(args[0])) {
            params = args[0];
        } else {
            params = args;
        }

        const executor = this.currentTransaction || this.client;

        try {
            const result = await executor.execute({
                sql: sql,
                args: params || [],
            });
            const rows = result.rows.map(r => this._rowToObj(r));
            if (callback) callback(null, rows);
            return rows;
        } catch (error) {
            console.error('Turso all error:', error);
            if (callback) {
                callback(error);
                return [];
            }
            throw error;
        }
    }

    // Convert libSQL row to standard JS object
    _rowToObj(row) {
        if (!row) return null;
        // libSQL rows can be accessed by column name, but let's ensure it looks like a plain object
        const obj = {};
        for (const key in row) {
            obj[key] = row[key];
        }
        return obj;
    }

    serialize(callback) {
        // Turso is always serialized in this context
        if (callback) callback();
    }

    exec(sql, callback) {
        // exec is basically run without params
        this.run(sql, [], callback);
    }

    prepare(sql) {
        // Simple mock for prepare
        return {
            run: (...args) => this.run(sql, ...args),
            finalize: () => { }
        };
    }

    close(callback) {
        if (callback) callback(null);
    }
}

const db = new TursoWrapper(turso);
db.currentTransaction = null;

module.exports = db;

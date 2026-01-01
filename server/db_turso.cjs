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
    }

    async run(sql, params, callback) {
        if (typeof params === 'function') {
            callback = params;
            params = [];
        }
        try {
            const result = await this.client.execute({
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
                return null; // Return resolved promise to avoid unhandled rejection
            }
            throw error;
        }
    }

    async get(sql, params, callback) {
        if (typeof params === 'function') {
            callback = params;
            params = [];
        }
        try {
            const result = await this.client.execute({
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

    async all(sql, params, callback) {
        if (typeof params === 'function') {
            callback = params;
            params = [];
        }
        try {
            const result = await this.client.execute({
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
            run: (params, callback) => this.run(sql, params, callback),
            finalize: () => { }
        };
    }

    close(callback) {
        if (callback) callback(null);
    }
}

const db = new TursoWrapper(turso);

module.exports = db;

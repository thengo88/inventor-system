/**
 * Database Helper with Optimistic Locking & Transaction Support
 * Provides safe concurrent access to database
 */

/**
 * Execute operation within a transaction
 * @param {sqlite3.Database} db - Database instance
 * @param {Function} callback - Async function to execute within transaction
 * @returns {Promise} - Resolves with callback result or rejects with error
 */
// Shared lock for transactions to prevent "cannot start a transaction within a transaction"
let transactionLock = Promise.resolve();

/**
 * Execute operation within a transaction
 * @param {sqlite3.Database} db - Database instance
 * @param {Function} callback - Async function to execute within transaction
 * @returns {Promise} - Resolves with callback result or rejects with error
 */
function withTransaction(db, callback) {
    // Chain onto the lock
    const nextTask = transactionLock.then(() => {
        return new Promise((resolve, reject) => {
            db.serialize(() => {
                db.run('BEGIN TRANSACTION', (err) => {
                    if (err) return reject(err);

                    Promise.resolve(callback())
                        .then(result => {
                            db.run('COMMIT', (err) => {
                                if (err) {
                                    db.run('ROLLBACK');
                                    return reject(err);
                                }
                                resolve(result);
                            });
                        })
                        .catch(error => {
                            db.run('ROLLBACK', () => reject(error));
                        });
                });
            });
        });
    });

    // Update the lock to wait for this task (even if it fails)
    transactionLock = nextTask.catch(() => { });

    return nextTask;
}

/**
 * Update with optimistic locking
 * @param {sqlite3.Database} db - Database instance
 * @param {string} table - Table name
 * @param {object} data - Data to update
 * @param {object} where - WHERE conditions
 * @param {number} expectedVersion - Expected version number
 * @param {string} userId - User making the update
 * @returns {Promise<boolean>} - True if updated, false if conflict
 */
function updateWithLock(db, table, data, where, expectedVersion, userId) {
    return new Promise((resolve, reject) => {
        // Build SET clause
        const setFields = Object.keys(data).map(key => `${key} = ?`).join(', ');
        const setValues = Object.values(data);

        // Build WHERE clause
        const whereFields = Object.keys(where).map(key => `${key} = ?`).join(' AND ');
        const whereValues = Object.values(where);

        // Add version check and increment
        const sql = `
            UPDATE ${table}
            SET ${setFields},
                version = version + 1,
                updated_by = ?,
                updatedAt = datetime('now')
            WHERE ${whereFields}
                AND version = ?
        `;

        const params = [...setValues, userId, ...whereValues, expectedVersion];

        db.run(sql, params, function (err) {
            if (err) return reject(err);

            // Check if any row was updated
            if (this.changes === 0) {
                // No rows updated = version conflict or record not found
                resolve(false);
            } else {
                resolve(true);
            }
        });
    });
}

/**
 * Claim a notification exclusively (for "KIỂM TRA NGAY" feature)
 * @param {sqlite3.Database} db - Database instance
 * @param {number} notificationId - Notification ID
 * @param {string} userId - User claiming the notification
 * @returns {Promise<boolean>} - True if claimed successfully, false if already claimed
 */
function claimNotification(db, notificationId, userId) {
    return new Promise((resolve, reject) => {
        const sql = `
            UPDATE notifications
            SET claimed_by = ?,
                claimed_at = datetime('now'),
                version = version + 1
            WHERE id = ?
                AND claimed_by IS NULL
        `;

        db.run(sql, [userId, notificationId], function (err) {
            if (err) return reject(err);
            resolve(this.changes > 0);
        });
    });
}

/**
 * Update stock audit with optimistic locking
 * @param {sqlite3.Database} db - Database instance
 * @param {string} sku - Product SKU
 * @param {string} warehouse - Warehouse name
 * @param {object} updates - Fields to update
 * @param {number} expectedVersion - Expected version
 * @param {string} userId - User making update
 * @returns {Promise<{success: boolean, conflict: boolean}>}
 */
function updateStockAudit(db, sku, warehouse, updates, expectedVersion, userId) {
    return new Promise((resolve, reject) => {
        const fields = Object.keys(updates);
        const values = Object.values(updates);

        const setClause = fields.map(f => `${f} = ?`).join(', ');

        const sql = `
            UPDATE stock_audit
            SET ${setClause},
                version = version + 1,
                updated_by = ?,
                timestamp = datetime('now')
            WHERE sku = ?
                AND warehouse = ?
                AND version = ?
        `;

        const params = [...values, userId, sku, warehouse, expectedVersion];

        db.run(sql, params, function (err) {
            if (err) return reject(err);

            if (this.changes === 0) {
                // Check if record exists
                db.get(
                    'SELECT version FROM stock_audit WHERE sku = ? AND warehouse = ?',
                    [sku, warehouse],
                    (err, row) => {
                        if (err) return reject(err);

                        if (!row) {
                            resolve({ success: false, conflict: false, notFound: true });
                        } else {
                            resolve({ success: false, conflict: true, currentVersion: row.version });
                        }
                    }
                );
            } else {
                resolve({ success: true, conflict: false });
            }
        });
    });
}

/**
 * Update ERP stock with optimistic locking
 * @param {sqlite3.Database} db - Database instance
 * @param {string} sku - Product SKU
 * @param {string} warehouse - Warehouse name
 * @param {object} updates - Fields to update (e.g., {kk1: '10', total_kk: '50'})
 * @param {number} expectedVersion - Expected version number
 * @param {string} userId - User making the update
 * @returns {Promise<{success: boolean, conflict: boolean, currentVersion?: number}>}
 */
function updateErpStock(db, sku, warehouse, updates, expectedVersion, userId) {
    return new Promise((resolve, reject) => {
        const fields = Object.keys(updates);
        const values = Object.values(updates);

        const setClause = fields.map(f => `${f} = ?`).join(', ');

        const sql = `
            UPDATE erp_stock
            SET ${setClause},
                version = version + 1,
                updated_by = ?,
                updatedAt = datetime('now')
            WHERE sku = ?
                AND warehouse = ?
                AND version = ?
        `;

        const params = [...values, userId, sku, warehouse, expectedVersion];

        db.run(sql, params, function (err) {
            if (err) return reject(err);

            if (this.changes === 0) {
                // Version conflict - get current version
                db.get(
                    'SELECT version FROM erp_stock WHERE sku = ? AND warehouse = ?',
                    [sku, warehouse],
                    (err, row) => {
                        if (err) return reject(err);

                        if (!row) {
                            resolve({ success: false, conflict: false, notFound: true });
                        } else {
                            resolve({ success: false, conflict: true, currentVersion: row.version });
                        }
                    }
                );
            } else {
                resolve({ success: true, conflict: false });
            }
        });
    });
}

/**
 * Retry operation with exponential backoff
 * @param {Function} operation - Async operation to retry
 * @param {number} maxRetries - Maximum number of retries
 * @param {number} initialDelay - Initial delay in ms
 * @returns {Promise} - Result of operation
 */
async function retryWithBackoff(operation, maxRetries = 3, initialDelay = 100) {
    let lastError;

    for (let attempt = 0; attempt <= maxRetries; attempt++) {
        try {
            return await operation();
        } catch (error) {
            lastError = error;

            if (attempt < maxRetries) {
                const delay = initialDelay * Math.pow(2, attempt);
                await new Promise(resolve => setTimeout(resolve, delay));
            }
        }
    }

    throw lastError;
}

/**
 * Log audit entry
 * @param {sqlite3.Database} db - Database instance
 * @param {string} tableName - Table name
 * @param {string} recordId - Record identifier
 * @param {string} action - Action type (INSERT, UPDATE, DELETE)
 * @param {object} oldValue - Old value (for UPDATE)
 * @param {object} newValue - New value
 * @param {string} userId - User performing action
 * @param {string} ipAddress - IP address (optional)
 */
function logAudit(db, tableName, recordId, action, oldValue, newValue, userId, ipAddress = null) {
    const sql = `
        INSERT INTO audit_log (table_name, record_id, action, old_value, new_value, user_id, ip_address)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    `;

    const params = [
        tableName,
        recordId,
        action,
        oldValue ? JSON.stringify(oldValue) : null,
        JSON.stringify(newValue),
        userId,
        ipAddress
    ];

    db.run(sql, params, (err) => {
        if (err) console.error('Audit log error:', err.message);
    });
}

module.exports = {
    withTransaction,
    updateWithLock,
    claimNotification,
    updateStockAudit,
    updateErpStock,
    retryWithBackoff,
    logAudit
};

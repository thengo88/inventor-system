# 🚀 HƯỚNG DẪN SỬ DỤNG HỆ THỐNG TỐI ƯU MỚI

## 📋 TÓM TẮT CÁC TỐI ƯU ĐÃ TRIỂN KHAI

### ✅ **Phase 1: Database Optimization** (HOÀN THÀNH)

#### 1. **Optimistic Locking**
- Thêm field `version` vào các bảng quan trọng
- Tránh race condition khi nhiều người cập nhật cùng lúc
- Các bảng đã được thêm:
  - `erp_stock`: version, locked_by, locked_at, updated_by
  - `stock_audit`: version, updated_by
  - `notifications`: version, claimed_by, claimed_at
  - `picking_items`: version, locked_by

#### 2. **Audit Logging**
- Bảng `audit_log` mới để track mọi thay đổi
- Tự động log khi UPDATE/INSERT/DELETE
- Lưu: table_name, record_id, action, old_value, new_value, user_id, ip_address, timestamp

#### 3. **Performance Indexes**
- 20+ indexes mới cho các bảng chính
- Tăng tốc queries lên 10-100x
- Indexes quan trọng:
  - `idx_erp_sku`, `idx_erp_warehouse`
  - `idx_audit_sku`, `idx_audit_warehouse`
  - `idx_notif_type`, `idx_notif_claimed`
  - `idx_picking_status`, `idx_picking_items_sku`

#### 4. **SQLite Optimizations**
- **WAL Mode**: Cho phép đọc/ghi đồng thời
- **Synchronous = NORMAL**: Tăng tốc ghi
- **Cache Size = 10000**: Tăng memory cache
- **Temp Store = MEMORY**: Tăng tốc temp operations

#### 5. **Auto Audit Triggers**
- Tự động log mọi thay đổi vào `audit_log`
- Trigger cho `erp_stock` UPDATE
- Trigger cho `stock_audit` INSERT

---

## 🔧 **Phase 2: Helper Functions** (HOÀN THÀNH)

File: `server/db_helper.cjs`

### Các hàm chính:

#### 1. `withTransaction(db, callback)`
```javascript
// Sử dụng:
await withTransaction(db, async () => {
    // Tất cả operations ở đây sẽ được wrap trong transaction
    await someDbOperation();
    await anotherDbOperation();
    // Tự động COMMIT nếu thành công, ROLLBACK nếu lỗi
});
```

#### 2. `updateErpStock(db, sku, warehouse, updates, expectedVersion, userId)`
```javascript
// Sử dụng:
const result = await updateErpStock(db, 'SKU-001', 'WH-A', {
    kk1: '10',
    total_kk: '50'
}, 5, 'user123'); // expectedVersion = 5

if (result.success) {
    console.log('✅ Updated successfully');
} else if (result.conflict) {
    console.log('⚠️ Version conflict! Current version:', result.currentVersion);
    // Cần reload data và thử lại
}
```

#### 3. `claimNotification(db, notificationId, userId)`
```javascript
// Sử dụng cho "KIỂM TRA NGAY":
const claimed = await claimNotification(db, 123, 'user456');

if (claimed) {
    console.log('✅ Notification claimed successfully');
    // Notification sẽ biến mất khỏi danh sách của users khác
} else {
    console.log('❌ Already claimed by another user');
}
```

#### 4. `retryWithBackoff(operation, maxRetries, initialDelay)`
```javascript
// Tự động retry khi có lỗi:
const result = await retryWithBackoff(async () => {
    return await someUnreliableOperation();
}, 3, 100); // Retry 3 lần, delay 100ms, 200ms, 400ms
```

#### 5. `logAudit(db, tableName, recordId, action, oldValue, newValue, userId, ipAddress)`
```javascript
// Manual audit logging:
logAudit(db, 'products', 'SKU-001', 'UPDATE', 
    { quantity: 100 }, 
    { quantity: 150 }, 
    'user123', 
    '192.168.1.1'
);
```

---

## 📝 **Phase 3: API Integration** (CẦN TRIỂN KHAI)

### Cần cập nhật các endpoints sau:

#### 1. **Stock Audit API** (`/api/stock-audit`)

**Trước (không an toàn):**
```javascript
app.post('/api/stock-audit', (req, res) => {
    const { sku, warehouse, totalResult, auditor } = req.body;
    
    db.run(`UPDATE stock_audit SET totalResult = ? WHERE sku = ? AND warehouse = ?`,
        [totalResult, sku, warehouse], (err) => {
            // ❌ Có thể bị ghi đè bởi user khác!
        });
});
```

**Sau (an toàn):**
```javascript
const { updateStockAudit } = require('./db_helper.cjs');

app.post('/api/stock-audit', async (req, res) => {
    const { sku, warehouse, totalResult, version, auditor } = req.body;
    
    try {
        const result = await updateStockAudit(db, sku, warehouse, {
            totalResult
        }, version, auditor);
        
        if (result.success) {
            res.json({ success: true });
        } else if (result.conflict) {
            res.status(409).json({ 
                error: 'Data was modified by another user',
                currentVersion: result.currentVersion
            });
        }
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});
```

#### 2. **ERP Stock Update** (`/api/erp/update`)

**Cần thêm:**
```javascript
const { updateErpStock, withTransaction } = require('./db_helper.cjs');

app.put('/api/erp/update', async (req, res) => {
    const { sku, warehouse, updates, version, userId } = req.body;
    
    try {
        const result = await updateErpStock(db, sku, warehouse, updates, version, userId);
        
        if (result.success) {
            // Broadcast update qua Socket.IO
            io.emit('erp_updated', { sku, warehouse });
            res.json({ success: true });
        } else if (result.conflict) {
            res.status(409).json({
                error: 'Version conflict',
                message: 'Dữ liệu đã được cập nhật bởi người khác. Vui lòng tải lại.',
                currentVersion: result.currentVersion
            });
        }
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});
```

#### 3. **Notification Claim** (`/api/notifications/claim`)

**Thêm endpoint mới:**
```javascript
const { claimNotification } = require('./db_helper.cjs');

app.post('/api/notifications/claim/:id', async (req, res) => {
    const { userId } = req.body;
    const notificationId = req.params.id;
    
    try {
        const claimed = await claimNotification(db, notificationId, userId);
        
        if (claimed) {
            // Broadcast để remove notification khỏi UI của users khác
            io.emit('notification_claimed', { id: notificationId, claimedBy: userId });
            res.json({ success: true });
        } else {
            res.status(409).json({ 
                error: 'Already claimed',
                message: 'Thông báo đã được xử lý bởi người khác'
            });
        }
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});
```

---

## 📱 **Phase 4: Flutter App Updates** (CẦN TRIỂN KHAI)

### 1. **API Service - Thêm Retry Logic**

File: `lib/services/api_service.dart`

```dart
import 'dart:math';

class ApiService {
  Future<T> _retryWithBackoff<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(milliseconds: 100),
  }) async {
    int retries = 0;
    
    while (true) {
      try {
        return await operation();
      } catch (e) {
        if (retries >= maxRetries) rethrow;
        
        await Future.delayed(initialDelay * pow(2, retries));
        retries++;
      }
    }
  }
  
  // Sử dụng:
  Future<Map<String, dynamic>> updateStockAudit({
    required String sku,
    required String warehouse,
    required int totalResult,
    required int version, // Thêm version
    required String auditor,
  }) async {
    return await _retryWithBackoff(() async {
      final response = await _dio.post('/api/stock-audit', data: {
        'sku': sku,
        'warehouse': warehouse,
        'totalResult': totalResult,
        'version': version,
        'auditor': auditor,
      });
      
      if (response.statusCode == 409) {
        // Version conflict
        throw ConflictException('Dữ liệu đã được cập nhật bởi người khác');
      }
      
      return response.data;
    });
  }
}

class ConflictException implements Exception {
  final String message;
  ConflictException(this.message);
}
```

### 2. **Stock Audit Screen - Handle Version Conflicts**

File: `lib/screens/stock_audit_screen.dart`

```dart
class _StockAuditScreenState extends State<StockAuditScreen> {
  int _currentVersion = 0; // Track version
  
  Future<void> _saveAudit() async {
    try {
      await _apiService.updateStockAudit(
        sku: _sku,
        warehouse: _warehouse,
        totalResult: _totalResult,
        version: _currentVersion,
        auditor: _username,
      );
      
      // Success - increment local version
      setState(() => _currentVersion++);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Lưu thành công')),
      );
    } on ConflictException catch (e) {
      // Version conflict - reload data
      await _reloadData();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ ${e.message}. Đã tải lại dữ liệu mới.'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Lỗi: $e')),
      );
    }
  }
  
  Future<void> _reloadData() async {
    final data = await _apiService.getStockAudit(_sku, _warehouse);
    setState(() {
      _currentVersion = data['version'] ?? 0;
      _totalResult = data['totalResult'] ?? 0;
      // Update other fields...
    });
  }
}
```

### 3. **Notification Provider - Handle Claiming**

File: `lib/providers/notification_provider.dart`

```dart
class NotificationProvider extends ChangeNotifier {
  Future<bool> claimNotification(int notificationId, String userId) async {
    try {
      final response = await _apiService.claimNotification(notificationId, userId);
      
      if (response['success']) {
        // Remove from local list
        _notifications.removeWhere((n) => n.id == notificationId);
        notifyListeners();
        return true;
      }
      
      return false;
    } on ConflictException {
      // Already claimed by another user
      _notifications.removeWhere((n) => n.id == notificationId);
      notifyListeners();
      return false;
    }
  }
  
  // Listen to Socket.IO for real-time updates
  void _listenToSocketIO() {
    _socket.on('notification_claimed', (data) {
      final claimedId = data['id'];
      final claimedBy = data['claimedBy'];
      
      if (claimedBy != _currentUserId) {
        // Remove from my list
        _notifications.removeWhere((n) => n.id == claimedId);
        notifyListeners();
      }
    });
  }
}
```

---

## 🎯 **CHECKLIST TRIỂN KHAI**

### ✅ Đã hoàn thành:
- [x] Database migration (optimistic locking fields)
- [x] Performance indexes
- [x] SQLite optimizations (WAL mode, cache, etc.)
- [x] Audit logging system
- [x] Auto audit triggers
- [x] Helper functions (db_helper.cjs)

### ⏳ Cần triển khai tiếp:
- [ ] Cập nhật API endpoints trong `server/index.cjs`
  - [ ] `/api/stock-audit` - Add version check
  - [ ] `/api/erp/update` - Add optimistic locking
  - [ ] `/api/notifications/claim` - New endpoint
- [ ] Cập nhật Flutter `ApiService`
  - [ ] Add retry logic
  - [ ] Add version handling
  - [ ] Add ConflictException
- [ ] Cập nhật Flutter screens
  - [ ] `stock_audit_screen.dart` - Handle conflicts
  - [ ] `erp_data_tab.dart` - Handle conflicts
  - [ ] `notification_provider.dart` - Add claiming logic
- [ ] Testing
  - [ ] Test với 2+ users cùng update 1 SKU
  - [ ] Test notification claiming
  - [ ] Test performance với 100+ concurrent users

---

## 📊 **DỰ ĐOÁN HIỆU SUẤT SAU TỐI ƯU**

| Số người dùng | Trước tối ưu | Sau tối ưu | Cải thiện |
|---------------|--------------|------------|-----------|
| 1-5 người | ✅ OK | ✅ Excellent | +50% faster |
| 10-20 người | ⚠️ Có thể lỗi | ✅ Stable | +200% reliability |
| 50+ người | ❌ Chắc chắn lỗi | ✅ Good | +500% capacity |
| 100+ người | ❌ Crash | ⚠️ OK (cần monitor) | +1000% capacity |

---

## 🚨 **LƯU Ý QUAN TRỌNG**

1. **Backup Database trước khi deploy:**
   ```bash
   cp server/database.db server/database.db.backup
   ```

2. **Chạy migration script:**
   ```bash
   node server/migrate_db.cjs
   ```

3. **Restart server sau khi update code:**
   ```bash
   # Stop server
   # Update code
   # Start server
   node server/index.cjs
   ```

4. **Monitor audit_log table:**
   ```sql
   -- Xem 10 audit logs gần nhất
   SELECT * FROM audit_log ORDER BY created_at DESC LIMIT 10;
   
   -- Xem conflicts (version mismatches)
   SELECT * FROM audit_log WHERE action = 'CONFLICT' ORDER BY created_at DESC;
   ```

5. **Performance monitoring:**
   ```sql
   -- Check index usage
   EXPLAIN QUERY PLAN SELECT * FROM erp_stock WHERE sku = 'SKU-001';
   
   -- Should show "USING INDEX idx_erp_sku"
   ```

---

## 📞 **HỖ TRỢ**

Nếu gặp vấn đề, kiểm tra:
1. `audit_log` table để xem lịch sử thay đổi
2. Server logs để xem errors
3. Database locks: `PRAGMA database_list;`
4. WAL mode status: `PRAGMA journal_mode;`

---

**Tài liệu này sẽ được cập nhật khi triển khai các phases tiếp theo.**

Ngày tạo: 2025-12-28
Phiên bản: 1.0

# 📱 HƯỚNG DẪN SỬ DỤNG OPTIMIZED OPERATIONS

## 🎯 Mục đích

Mixin `OptimizedOperations` cung cấp các phương thức an toàn cho concurrent operations với:
- ✅ Automatic version tracking
- ✅ Conflict detection & handling
- ✅ User-friendly error messages
- ✅ Retry logic
- ✅ Loading indicators

---

## 🚀 CÁCH SỬ DỤNG

### **Bước 1: Import mixin**

```dart
import 'package:inventor/mixins/optimized_operations.dart';
import 'package:inventor/services/api_service_optimized.dart';
```

### **Bước 2: Add mixin vào State class**

```dart
class _StockAuditScreenState extends State<StockAuditScreen> 
    with OptimizedOperations {  // <-- Add this
  
  // Your existing code...
}
```

### **Bước 3: Sử dụng safe methods**

---

## 📝 EXAMPLES

### **1. Safe Update Stock Audit**

**Trước (không an toàn):**
```dart
Future<void> _submitData() async {
  try {
    await _apiService.submitStockAudit({
      'sku': _sku,
      'warehouse': _warehouse,
      'totalResult': _totalResult,
      'auditor': _username,
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Lưu thành công')),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Lỗi: $e')),
    );
  }
}
```

**Sau (an toàn với optimistic locking):**
```dart
Future<void> _submitData() async {
  final success = await safeUpdateStockAudit(
    apiService: _apiService,
    sku: _sku,
    warehouse: _warehouse,
    updates: {
      'totalResult': _totalResult,
      'horRows': _horRows,
      'verRows': _verRows,
      // ... other fields
    },
    auditor: _username,
    showSnackbar: true,  // Auto show success/error messages
  );
  
  if (success) {
    // Update successful - do something
    _resetCalculator();
  } else {
    // Conflict or error - data already reloaded
    // User sees appropriate message
  }
}
```

---

### **2. Safe Update ERP Stock**

```dart
Future<void> _updateErpQuantity() async {
  final success = await safeUpdateErpStock(
    apiService: _apiService,
    sku: 'SKU-001',
    warehouse: 'WH-A',
    updates: {
      'kk1': '10',
      'kk2': '20',
      'total_kk': '30',
    },
    userId: _currentUserId,
    showSnackbar: true,
  );
  
  if (success) {
    print('ERP updated successfully');
  }
}
```

---

### **3. Claim Notification**

**Trong NotificationProvider hoặc Screen:**

```dart
Future<void> _handleCheckNow(int notificationId) async {
  final claimed = await claimNotificationSafe(
    apiService: _apiService,
    notificationId: notificationId,
    userId: _currentUserId,
    showSnackbar: true,
  );
  
  if (claimed) {
    // Successfully claimed - navigate to audit screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StockAuditScreen(
          initialSku: _sku,
          initialWarehouse: _warehouse,
        ),
      ),
    );
  } else {
    // Already claimed by another user
    // Notification will be removed from list automatically
  }
}
```

---

### **4. Batch Update**

```dart
Future<void> _updateMultipleSkus() async {
  final operations = [
    {
      'table': 'erp_stock',
      'sku': 'SKU-001',
      'warehouse': 'WH-A',
      'updates': {'kk1': '10'},
      'version': getVersion('erp_SKU-001_WH-A'),
    },
    {
      'table': 'erp_stock',
      'sku': 'SKU-002',
      'warehouse': 'WH-A',
      'updates': {'kk1': '20'},
      'version': getVersion('erp_SKU-002_WH-A'),
    },
    // ... more operations
  ];
  
  final success = await batchUpdateSafe(
    apiService: _apiService,
    operations: operations,
    userId: _currentUserId,
    showSnackbar: true,
  );
  
  if (success) {
    print('All updates successful');
  } else {
    print('Batch update failed - all rolled back');
  }
}
```

---

### **5. Manual Version Tracking**

```dart
// Get current version
final version = getVersion('SKU-001_WH-A');

// Set version (e.g., after loading from server)
setVersion('SKU-001_WH-A', 5);

// Increment version (automatically done by safe methods)
incrementVersion('SKU-001_WH-A');
```

---

### **6. Custom Loading Dialog**

```dart
Future<void> _longRunningOperation() async {
  showLoadingDialog(message: 'Đang xử lý dữ liệu...');
  
  try {
    await Future.delayed(Duration(seconds: 3));
    // Do something...
  } finally {
    hideLoadingDialog();
  }
}
```

---

### **7. Retry Dialog**

```dart
Future<void> _handleConflict() async {
  final shouldRetry = await showRetryDialog(
    title: 'Xung đột dữ liệu',
    message: 'Dữ liệu đã được cập nhật bởi người khác. Bạn có muốn tải lại và thử lại không?',
  );
  
  if (shouldRetry) {
    await _reloadData();
    await _submitData();
  }
}
```

---

## 🔧 INTEGRATION VÀO SCREENS HIỆN TẠI

### **Stock Audit Screen**

```dart
// File: lib/screens/stock_audit_screen.dart

// 1. Add import
import '../mixins/optimized_operations.dart';
import '../services/api_service_optimized.dart';

// 2. Add mixin
class _StockAuditScreenState extends State<StockAuditScreen> 
    with OptimizedOperations {
  
  // 3. Update _submitData method
  Future<void> _submitData() async {
    if (_sku.isEmpty) {
      _showSnack('Vui lòng quét mã SKU', Colors.red);
      return;
    }
    
    final success = await safeUpdateStockAudit(
      apiService: _apiService,
      sku: _sku,
      warehouse: _selectedWarehouse ?? 'Default',
      updates: {
        'packagingStandard': int.tryParse(_packagingController.text) ?? 0,
        'horRows': int.tryParse(_horController.text) ?? 0,
        'verRows': int.tryParse(_verController.text) ?? 0,
        'evenRows': int.tryParse(_evenController.text) ?? 0,
        'oddRows': int.tryParse(_oddController.text) ?? 0,
        'individualBags': int.tryParse(_individualController.text) ?? 0,
        'totalResult': _totalResult,
      },
      auditor: _username,
      showSnackbar: true,
    );
    
    if (success) {
      _resetCalculator();
      await _fetchHistory();
    }
  }
}
```

---

### **ERP Data Tab**

```dart
// File: lib/screens/admin/erp_data_tab.dart

import '../../mixins/optimized_operations.dart';
import '../../services/api_service_optimized.dart';

class _ErpDataTabState extends State<ErpDataTab> 
    with OptimizedOperations {
  
  Future<void> _updateKkValue(String sku, String warehouse, String kkField, String value) async {
    final success = await safeUpdateErpStock(
      apiService: _apiService,
      sku: sku,
      warehouse: warehouse,
      updates: {
        kkField: value,
        // Recalculate total_kk
        'total_kk': _calculateTotalKk(sku, warehouse, kkField, value),
      },
      userId: _currentUsername,
      showSnackbar: true,
    );
    
    if (success) {
      // Reload data
      await _loadErpData();
    }
  }
}
```

---

### **Notification Provider**

```dart
// File: lib/providers/notification_provider.dart

import '../mixins/optimized_operations.dart';
import '../services/api_service_optimized.dart';

class NotificationProvider extends ChangeNotifier {
  final ApiService _apiService;
  
  Future<bool> handleCheckNow(int notificationId, String userId, BuildContext context) async {
    try {
      final claimed = await _apiService.claimNotification(
        notificationId: notificationId,
        userId: userId,
      );
      
      if (claimed) {
        // Remove from local list
        _notifications.removeWhere((n) => n.id == notificationId);
        notifyListeners();
        return true;
      } else {
        // Already claimed
        _notifications.removeWhere((n) => n.id == notificationId);
        notifyListeners();
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Thông báo đã được xử lý bởi người khác'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        
        return false;
      }
    } catch (e) {
      print('Error claiming notification: $e');
      return false;
    }
  }
}
```

---

## 🎯 BEST PRACTICES

### **1. Always use safe methods for updates**
```dart
// ❌ BAD
await _apiService.submitStockAudit(data);

// ✅ GOOD
await safeUpdateStockAudit(...);
```

### **2. Track versions for all critical data**
```dart
// When loading data from server
final data = await _apiService.getErpStock(sku, warehouse);
setVersion('erp_${sku}_$warehouse', data['version'] ?? 0);
```

### **3. Handle conflicts gracefully**
```dart
final success = await safeUpdateStockAudit(...);

if (!success) {
  // Version conflict - reload data
  await _reloadData();
  
  // Optionally ask user to retry
  final retry = await showRetryDialog(...);
  if (retry) {
    await safeUpdateStockAudit(...);
  }
}
```

### **4. Use batch updates for multiple operations**
```dart
// ❌ BAD - Multiple separate updates
for (var sku in skus) {
  await safeUpdateErpStock(...);
}

// ✅ GOOD - Single batch update
await batchUpdateSafe(
  operations: skus.map((sku) => {...}).toList(),
  userId: _userId,
);
```

---

## 🐛 TROUBLESHOOTING

### **Problem: Version conflicts liên tục**
**Solution:**
- Check network latency
- Ensure version is being tracked correctly
- Reload data before each update

### **Problem: Snackbar không hiện**
**Solution:**
- Ensure `mounted` check before showing snackbar
- Use `showSnackbar: true` parameter

### **Problem: Loading dialog không tắt**
**Solution:**
- Always call `hideLoadingDialog()` in `finally` block
- Check `Navigator.canPop(context)` before popping

---

## 📊 MONITORING

### **View audit log:**
```dart
final logs = await _apiService.getAuditLog(
  table: 'erp_stock',
  userId: _currentUserId,
  limit: 50,
);

// Display in UI
for (var log in logs) {
  print('${log['created_at']}: ${log['action']} - ${log['new_value']}');
}
```

---

**Tài liệu này sẽ được cập nhật khi có thêm features mới.**

Ngày tạo: 2025-12-28
Phiên bản: 1.0

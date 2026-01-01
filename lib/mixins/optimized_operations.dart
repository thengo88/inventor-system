import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/api_service_optimized.dart';

/// Mixin to add optimized concurrent-safe operations to screens
/// Usage: class _MyScreenState extends State<MyScreen> with OptimizedOperations
mixin OptimizedOperations<T extends StatefulWidget> on State<T> {
  /// Track current version for optimistic locking
  final Map<String, int> _versions = {};

  /// Get current version for a record
  int getVersion(String key) => _versions[key] ?? 0;

  /// Set version for a record
  void setVersion(String key, int version) {
    _versions[key] = version;
  }

  /// Increment version after successful update
  void incrementVersion(String key) {
    _versions[key] = (_versions[key] ?? 0) + 1;
  }

  /// Safe update stock audit with automatic conflict handling
  Future<bool> safeUpdateStockAudit({
    required ApiService apiService,
    required String sku,
    required String warehouse,
    required Map<String, dynamic> updates,
    required String auditor,
    bool showSnackbar = true,
  }) async {
    final versionKey = '${sku}_$warehouse';
    final currentVersion = getVersion(versionKey);

    try {
      await apiService.safeUpdateStockAudit(
        sku: sku,
        warehouse: warehouse,
        updates: updates,
        version: currentVersion,
        auditor: auditor,
      );

      // Success - increment version
      incrementVersion(versionKey);

      if (showSnackbar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Lưu thành công'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }

      return true;
    } on ConflictException catch (e) {
      // Version conflict - reload data
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ ${e.message}\nĐang tải lại dữ liệu...'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // Update to latest version
      if (e.currentVersion != null) {
        setVersion(versionKey, e.currentVersion!);
      }

      return false;
    } on NotFoundException catch (e) {
      if (showSnackbar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }

      return false;
    } catch (e) {
      if (showSnackbar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Lỗi: $e'), backgroundColor: Colors.red),
        );
      }

      return false;
    }
  }

  /// Safe update ERP stock with automatic conflict handling
  Future<bool> safeUpdateErpStock({
    required ApiService apiService,
    required String sku,
    required String warehouse,
    required Map<String, dynamic> updates,
    required String userId,
    bool showSnackbar = true,
  }) async {
    final versionKey = 'erp_${sku}_$warehouse';
    final currentVersion = getVersion(versionKey);

    try {
      await apiService.safeUpdateErpStock(
        sku: sku,
        warehouse: warehouse,
        updates: updates,
        version: currentVersion,
        userId: userId,
      );

      // Success
      incrementVersion(versionKey);

      if (showSnackbar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Cập nhật ERP thành công'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }

      return true;
    } on ConflictException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ ${e.message}\nVui lòng tải lại dữ liệu.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      if (e.currentVersion != null) {
        setVersion(versionKey, e.currentVersion!);
      }

      return false;
    } catch (e) {
      if (showSnackbar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Lỗi: $e'), backgroundColor: Colors.red),
        );
      }

      return false;
    }
  }

  /// Claim notification with automatic UI feedback
  Future<bool> claimNotificationSafe({
    required ApiService apiService,
    required int notificationId,
    required String userId,
    bool showSnackbar = true,
  }) async {
    try {
      final claimed = await apiService.claimNotification(
        notificationId: notificationId,
        userId: userId,
      );

      if (!claimed) {
        if (showSnackbar && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Thông báo đã được xử lý bởi người khác'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }

      return claimed;
    } catch (e) {
      if (showSnackbar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Lỗi khi claim notification: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }

      return false;
    }
  }

  /// Show loading dialog
  void showLoadingDialog({String message = 'Đang xử lý...'}) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }

  /// Hide loading dialog
  void hideLoadingDialog() {
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  /// Show retry dialog on conflict
  Future<bool> showRetryDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.orange),
            const SizedBox(width: 10),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Tải lại & Thử lại'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  /// Batch update with transaction
  Future<bool> batchUpdateSafe({
    required ApiService apiService,
    required List<Map<String, dynamic>> operations,
    required String userId,
    bool showSnackbar = true,
  }) async {
    try {
      showLoadingDialog(
        message: 'Đang cập nhật ${operations.length} bản ghi...',
      );

      await apiService.batchUpdate(operations: operations, userId: userId);

      hideLoadingDialog();

      if (showSnackbar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Cập nhật thành công ${operations.length} bản ghi'),
            backgroundColor: Colors.green,
          ),
        );
      }

      return true;
    } catch (e) {
      hideLoadingDialog();

      if (showSnackbar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Lỗi batch update: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }

      return false;
    }
  }
}

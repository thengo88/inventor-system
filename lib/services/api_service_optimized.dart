import 'dart:async';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_service.dart';

/// Exception thrown when version conflict occurs (HTTP 409)
class ConflictException implements Exception {
  final String message;
  final int? currentVersion;

  ConflictException(this.message, {this.currentVersion});

  @override
  String toString() => 'ConflictException: $message';
}

/// Exception thrown when resource not found (HTTP 404)
class NotFoundException implements Exception {
  final String message;

  NotFoundException(this.message);

  @override
  String toString() => 'NotFoundException: $message';
}

/// Extension for ApiService with optimized concurrent-safe methods
extension ApiServiceOptimized on ApiService {
  /// Retry operation with exponential backoff
  Future<T> retryWithBackoff<T>(
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

        // Exponential backoff: 100ms, 200ms, 400ms
        final delay = initialDelay * pow(2, retries);
        await Future.delayed(delay);
        retries++;
      }
    }
  }

  /// Safe update stock audit with optimistic locking
  Future<Map<String, dynamic>> safeUpdateStockAudit({
    required String sku,
    required String warehouse,
    required Map<String, dynamic> updates,
    required int version,
    required String auditor,
  }) async {
    final url = Uri.parse('$baseUrl/stock-audit/safe-update');

    final response = await retryWithBackoff(() async {
      return await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'sku': sku,
          'warehouse': warehouse,
          'updates': updates,
          'version': version,
          'auditor': auditor,
        }),
      );
    });

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 409) {
      // Version conflict
      final data = json.decode(response.body);
      throw ConflictException(
        data['message'] ?? 'Version conflict',
        currentVersion: data['currentVersion'],
      );
    } else if (response.statusCode == 404) {
      final data = json.decode(response.body);
      throw NotFoundException(data['message'] ?? 'Record not found');
    } else {
      throw Exception('Failed to update stock audit: ${response.body}');
    }
  }

  /// Safe update ERP stock with optimistic locking
  Future<Map<String, dynamic>> safeUpdateErpStock({
    required String sku,
    required String warehouse,
    required Map<String, dynamic> updates,
    required int version,
    required String userId,
  }) async {
    final url = Uri.parse('$baseUrl/erp/safe-update');

    final response = await retryWithBackoff(() async {
      return await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'sku': sku,
          'warehouse': warehouse,
          'updates': updates,
          'version': version,
          'userId': userId,
        }),
      );
    });

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 409) {
      final data = json.decode(response.body);
      throw ConflictException(
        data['message'] ?? 'Version conflict',
        currentVersion: data['currentVersion'],
      );
    } else if (response.statusCode == 404) {
      final data = json.decode(response.body);
      throw NotFoundException(data['message'] ?? 'SKU not found');
    } else {
      throw Exception('Failed to update ERP stock: ${response.body}');
    }
  }

  /// Claim notification exclusively
  Future<bool> claimNotification({
    required int notificationId,
    required String userId,
  }) async {
    final url = Uri.parse('$baseUrl/notifications/claim/$notificationId');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'userId': userId}),
      );

      if (response.statusCode == 200) {
        return true;
      } else if (response.statusCode == 409) {
        // Already claimed by another user
        return false;
      } else {
        throw Exception('Failed to claim notification: ${response.body}');
      }
    } catch (e) {
      print('Error claiming notification: $e');
      return false;
    }
  }

  /// Batch update multiple records in a transaction
  Future<Map<String, dynamic>> batchUpdate({
    required List<Map<String, dynamic>> operations,
    required String userId,
  }) async {
    final url = Uri.parse('$baseUrl/batch-update');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'operations': operations, 'userId': userId}),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final data = json.decode(response.body);
      throw Exception(data['message'] ?? 'Batch update failed');
    }
  }

  /// Get audit log for debugging/compliance
  Future<List<Map<String, dynamic>>> getAuditLog({
    String? table,
    String? recordId,
    String? userId,
    int limit = 100,
    int offset = 0,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };

    if (table != null) queryParams['table'] = table;
    if (recordId != null) queryParams['recordId'] = recordId;
    if (userId != null) queryParams['userId'] = userId;

    final url = Uri.parse(
      '$baseUrl/audit-log',
    ).replace(queryParameters: queryParams);

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['logs']);
    } else {
      throw Exception('Failed to get audit log: ${response.body}');
    }
  }
}

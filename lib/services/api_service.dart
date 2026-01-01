import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';
import '../models/user.dart';
import '../models/log_entry.dart';
import '../models/picking_list.dart';

import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static String normalizeSku(String sku) {
    return sku.toString().replaceAll('-', '').trim().toUpperCase();
  }

  String _currentIp = '192.168.1.13'; // Default fallback
  IO.Socket? socket;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _currentIp = prefs.getString('server_ip') ?? '192.168.1.13';
    _initSocket();
  }

  // Dynamic base URL detection for Web
  bool get _isWeb => kIsWeb;

  String get _dynamicBaseUrl {
    if (_isWeb) {
      final uri = Uri.base;
      // If we are running on a custom port (like development), include it.
      // If we are on standard 80/443, port might be 0 or -1 in some implementations,
      // but Uri.base usually handles it correctly.
      if (uri.port == 80 ||
          uri.port == 443 ||
          uri.port == 0 ||
          uri.port == -1) {
        return '${uri.scheme}://${uri.host}';
      }
      return '${uri.scheme}://${uri.host}:${uri.port}';
    }

    // Fallback for Mobile (Android/iOS)
    if (_currentIp.startsWith('http://') || _currentIp.startsWith('https://')) {
      // User entered a full URL (e.g. from Render)
      return _currentIp.endsWith('/')
          ? _currentIp.substring(0, _currentIp.length - 1)
          : _currentIp;
    }
    // Backward compatibility: User entered just an IP
    return 'http://$_currentIp:3000';
  }

  void _initSocket() {
    socket?.dispose();

    final String socketUrl = _dynamicBaseUrl;

    socket = IO.io(socketUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      // Only needed if we are actually on HTTPS
      if (socketUrl.startsWith('https')) ...{
        'secure': true,
        'rejectUnauthorized': false,
      },
    });
    socket?.connect();
    socket?.onConnect((_) {
      print('Socket connected to $socketUrl');
    });
  }

  String get baseUrl => '$_dynamicBaseUrl/api';
  String get uploadUrl => _dynamicBaseUrl;

  Future<void> updateIp(String newIp) async {
    _currentIp = newIp;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_ip', newIp);
    _initSocket();
  }

  // Auth
  Future<Map<String, dynamic>?> login(String username, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('Login error: $e');
    }
    return null;
  }

  // Stock Audit
  Future<bool> submitStockAudit(Map<String, dynamic> auditData) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/stock-audit'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(auditData),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Submit stock audit error: $e');
      return false;
    }
  }

  // Products
  Future<List<Product>> getProducts() async {
    try {
      final response = await http.get(
        Uri.parse(
          '$baseUrl/products?t=${DateTime.now().millisecondsSinceEpoch}',
        ),
      );
      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        return data.map((item) => Product.fromMap(item)).toList();
      }
    } catch (e) {
      print('Get products error: $e');
    }
    return [];
  }

  Future<Product?> getProductBySku(String sku) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/products/$sku'));
      if (response.statusCode == 200) {
        return Product.fromMap(jsonDecode(response.body));
      }
    } catch (e) {
      print('Get product by SKU error: $e');
    }
    return null;
  }

  Future<bool> addProduct(
    Product product,
    File? imageFile,
    File? imageFile2,
  ) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/products'),
      );
      request.fields['sku'] = product.sku;
      request.fields['name'] = product.name;
      request.fields['packagingStandard'] = product.packagingStandard;
      request.fields['layoutPosition'] = product.layoutPosition;
      request.fields['customer'] = product.customer;
      request.fields['description'] = product.description ?? '';
      request.fields['stock'] = product.stock.toString();

      if (imageFile != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'image',
            imageFile.path,
            contentType: _getMediaType(imageFile.path),
          ),
        );
      }
      if (imageFile2 != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'image2',
            imageFile2.path,
            contentType: _getMediaType(imageFile2.path),
          ),
        );
      }

      var response = await request.send();
      return response.statusCode == 200;
    } catch (e) {
      print('Add product error: $e');
      return false;
    }
  }

  Future<bool> updateProduct(
    Product product,
    File? imageFile,
    File? imageFile2,
  ) async {
    try {
      var request = http.MultipartRequest(
        'PUT',
        Uri.parse('$baseUrl/products/${product.id}'),
      );
      request.fields['sku'] = product.sku;
      request.fields['name'] = product.name;
      request.fields['packagingStandard'] = product.packagingStandard;
      request.fields['layoutPosition'] = product.layoutPosition;
      request.fields['customer'] = product.customer;
      request.fields['description'] = product.description ?? '';
      request.fields['stock'] = product.stock.toString();

      if (imageFile != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'image',
            imageFile.path,
            contentType: _getMediaType(imageFile.path),
          ),
        );
      }
      if (imageFile2 != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'image2',
            imageFile2.path,
            contentType: _getMediaType(imageFile2.path),
          ),
        );
      }

      var response = await request.send();
      return response.statusCode == 200;
    } catch (e) {
      print('Update product error: $e');
      return false;
    }
  }

  MediaType _getMediaType(String path) {
    String ext = path.split('.').last.toLowerCase();
    if (ext == 'png') return MediaType('image', 'png');
    if (ext == 'jpg' || ext == 'jpeg') return MediaType('image', 'jpeg');
    return MediaType('image', ext.isEmpty ? 'jpeg' : ext);
  }

  Future<bool> deleteProduct(int id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/products/$id'));
      return response.statusCode == 200;
    } catch (e) {
      print('Delete product error: $e');
      return false;
    }
  }

  // --- Warehouse Config ---
  Future<Map<String, dynamic>?> getWarehouseConfig() async {
    try {
      final response = await http.get(
        Uri.parse(
          '$baseUrl/warehouse-config?t=${DateTime.now().millisecondsSinceEpoch}',
        ),
      ); // Anti-cache
      if (response.statusCode == 200) {
        if (response.body == 'null') return null;
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('Get warehouse config error: $e');
    }
    return null;
  }

  Future<bool> saveWarehouseConfig(Map<String, dynamic> config) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/warehouse-config'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(config),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Save warehouse config error: $e');
      return false;
    }
  }

  // Users
  Future<List<User>> getUsers() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/users'));
      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        return data
            .map((item) => User.fromMap({...item, 'password': ''}))
            .toList();
      }
    } catch (e) {
      print('Get users error: $e');
    }
    return [];
  }

  Future<bool> addUser(User user) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/users'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(user.toMap()),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Add user error: $e');
      return false;
    }
  }

  Future<bool> deleteUser(int id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/users/$id'));
      return response.statusCode == 200;
    } catch (e) {
      print('Delete user error: $e');
      return false;
    }
  }

  // Logs
  Future<List<LogEntry>> getLogs() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/logs'));
      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        return data.map((item) => LogEntry.fromMap(item)).toList();
      }
    } catch (e) {
      print('Get logs error: $e');
    }
    return [];
  }

  Future<void> addLog(LogEntry log) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/logs'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(log.toMap()),
      );
    } catch (e) {
      print('Add log error: $e');
    }
  }

  Future<bool> deleteLog(int id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/logs/$id'));
      return response.statusCode == 200;
    } catch (e) {
      print('Delete log error: $e');
      return false;
    }
  }

  Future<bool> deleteMultipleLogs(List<int> ids) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/logs/delete-multiple'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ids': ids}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Delete multiple logs error: $e');
      return false;
    }
  }

  Future<bool> deleteAllLogs() async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/logs/all'));
      return response.statusCode == 200;
    } catch (e) {
      print('Delete all logs error: $e');
      return false;
    }
  }

  Future<User?> getCurrentUser(String username) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/me/$username'));
      if (response.statusCode == 200) {
        return User.fromMap(jsonDecode(response.body));
      }
    } catch (e) {
      print('Get current user error: $e');
    }
    return null;
  }

  Future<bool> updateUser(
    int id, {
    String? password,
    required String role,
    String? assignedRecs,
    String? assignedTyps,
    String? assignedPs,
    String? assignedOprs,
    String? assignedTr,
    String? assignedGate,
    String? assignedLine,
    String? assignedZone,
    String? assignedBox,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/users/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (password != null && password.isNotEmpty) 'password': password,
          'role': role,
          'assignedRecs': assignedRecs,
          'assignedTyps': assignedTyps,
          'assignedPs': assignedPs,
          'assignedOprs': assignedOprs,
          'assignedTr': assignedTr,
          'assignedGate': assignedGate,
          'assignedLine': assignedLine,
          'assignedZone': assignedZone,
          'assignedBox': assignedBox,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Update user error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getUniqueFilterValues() async {
    try {
      print('Fetching unique values from: $baseUrl/picking/unique-values');
      final response = await http.get(
        Uri.parse('$baseUrl/picking/unique-values'),
      );
      print(
        'Unique values response (${response.statusCode}): ${response.body}',
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('Get unique values error: $e');
    }
    return null;
  }

  // Picking
  Future<List<PickingList>> getPickingLists({
    String? username,
    String? recs,
    String? typs,
    String? ps,
    String? oprs,
    String? tr,
    String? gate,
    String? line,
    String? zone,
    String? box,
    bool isFiltered = false,
  }) async {
    try {
      final query =
          'username=${username ?? ''}&recs=${recs ?? ''}&typs=${typs ?? ''}&ps=${ps ?? ''}&oprs=${oprs ?? ''}&tr=${tr ?? ''}&gate=${gate ?? ''}&line=${line ?? ''}&zone=${zone ?? ''}&box=${box ?? ''}&isFiltered=${isFiltered ? 1 : 0}';
      final response = await http.get(Uri.parse('$baseUrl/picking?$query'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((item) => PickingList.fromMap(item)).toList();
      }
    } catch (e) {
      print('Get picking lists error: $e');
    }
    return [];
  }

  Future<PickingList?> getPickingDetail(
    int id, {
    String? username,
    String? recs,
    String? typs,
    String? ps,
    String? oprs,
    String? tr,
    String? gate,
    String? line,
    String? zone,
    String? box,
    bool isFiltered = false,
  }) async {
    try {
      String query = '';
      List<String> paramsList = [];
      if (username != null && username.isNotEmpty)
        paramsList.add('username=$username');
      if (recs != null && recs.isNotEmpty) paramsList.add('recs=$recs');
      if (typs != null && typs.isNotEmpty) paramsList.add('typs=$typs');
      if (ps != null && ps.isNotEmpty) paramsList.add('ps=$ps');
      if (oprs != null && oprs.isNotEmpty) paramsList.add('oprs=$oprs');
      if (tr != null && tr.isNotEmpty) paramsList.add('tr=$tr');
      if (gate != null && gate.isNotEmpty) paramsList.add('gate=$gate');
      if (line != null && line.isNotEmpty) paramsList.add('line=$line');
      if (zone != null && zone.isNotEmpty) paramsList.add('zone=$zone');
      if (box != null && box.isNotEmpty) paramsList.add('box=$box');
      if (isFiltered) paramsList.add('isFiltered=1');
      if (paramsList.isNotEmpty) query = '?${paramsList.join('&')}';

      final url = Uri.parse('$baseUrl/picking/$id$query');
      print('Fetching picking detail: $url');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return PickingList.fromMap(decoded);
      } else {
        print(
          'Get picking detail failed (Status ${response.statusCode}): ${response.body}',
        );
      }
    } catch (e, stack) {
      print('Get picking detail error: $e');
      print(stack);
    }
    return null;
  }

  Future<List<dynamic>> getAssignmentProgress() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin/assignment-progress'),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('Get assignment progress error: $e');
    }
    return [];
  }

  Future<bool> createPickingList(
    String orderNumber,
    String customer,
    List<Map<String, dynamic>> items,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/picking'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'orderNumber': orderNumber,
          'customer': customer,
          'items': items,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Create picking list error: $e');
      return false;
    }
  }

  Future<List<String>?> getExcelSheets(File file) async {
    try {
      print('[ApiService] Getting sheets from: $baseUrl/picking/sheets');
      print('[ApiService] File path: ${file.path}');

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/picking/sheets'),
      );
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
          contentType: MediaType(
            'application',
            'vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ),
      );

      print('[ApiService] Sending request...');
      var response = await request.send();
      print('[ApiService] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        print('[ApiService] Response body: $respStr');
        final data = jsonDecode(respStr);
        final sheets = List<String>.from(data['sheets'] ?? []);
        print('[ApiService] Parsed sheets: $sheets');
        return sheets;
      } else {
        final respStr = await response.stream.bytesToString();
        print('[ApiService] Error response: $respStr');
      }
      return null;
    } catch (e) {
      print('[ApiService] Get Excel sheets error: $e');
      return null;
    }
  }

  Future<List<String>?> getExcelDates(
    File file, {
    String? selectedSheet,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/picking/dates'),
      );
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
          contentType: MediaType(
            'application',
            'vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ),
      );
      if (selectedSheet != null) {
        request.fields['selectedSheet'] = selectedSheet;
      }

      var response = await request.send();
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final data = jsonDecode(respStr);
        return List<String>.from(data['dates'] ?? []);
      }
      return null;
    } catch (e) {
      print('Get Excel dates error: $e');
      return null;
    }
  }

  Future<List<String>?> getExcelHeaders(
    File file, {
    String? selectedSheet,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/picking/headers'),
      );
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
          contentType: MediaType(
            'application',
            'vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ),
      );
      if (selectedSheet != null) {
        request.fields['selectedSheet'] = selectedSheet;
      }

      var response = await request.send();
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final data = jsonDecode(respStr);
        return List<String>.from(data['headers'] ?? []);
      }
      return null;
    } catch (e) {
      print('Get Excel headers error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> importExcelPickingList(
    String orderNumber,
    String customer,
    File file, {
    String? selectedSheet,
    String? selectedDate,
    Map<String, String>? columnMapping,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/picking/import'),
      );
      request.fields['orderNumber'] = orderNumber;
      request.fields['customer'] = customer;
      if (selectedSheet != null) {
        request.fields['selectedSheet'] = selectedSheet;
      }
      if (selectedDate != null) {
        request.fields['selectedDate'] = selectedDate;
      }
      if (columnMapping != null) {
        request.fields['columnMapping'] = jsonEncode(columnMapping);
      }
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
          contentType: MediaType(
            'application',
            'vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ),
      );

      var response = await request.send();
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        return jsonDecode(respStr) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('Import Excel error: $e');
      return null;
    }
  }

  Future<bool> assignPickingItems({
    required int listId,
    required String username,
    List<String>? recs,
    List<String>? trs,
    List<String>? gates,
    List<String>? lines,
    List<String>? zones,
    List<String>? typs,
    List<String>? boxes,
    List<String>? pscds,
    List<String>? oprs,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/picking/assign'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'listId': listId,
          'username': username,
          'recs': recs,
          'trs': trs,
          'gates': gates,
          'lines': lines,
          'zones': zones,
          'typs': typs,
          'boxes': boxes,
          'pscds': pscds,
          'oprs': oprs,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Assign picking items error: $e');
      return false;
    }
  }

  Future<bool> updatePickedQuantity(
    int itemId,
    int quantity,
    String username,
  ) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/picking/item/$itemId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'quantityPicked': quantity, 'username': username}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Update picked quantity error: $e');
      return false;
    }
  }

  Future<bool> addPickingHistory(Map<String, dynamic> historyData) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/picking/history'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(historyData),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Add picking history error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getPickingHistory() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/picking/history'));
      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      print('Get picking history error: $e');
    }
    return [];
  }

  Future<bool> clearPickingHistory() async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/picking/history/clear'),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Clear picking history error: $e');
      return false;
    }
  }

  Future<bool> updatePickingStatus(int listId, String status) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/picking/status/$listId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': status}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Update picking status error: $e');
      return false;
    }
  }

  Future<bool> deletePickingList(int id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/picking/$id'));
      return response.statusCode == 200;
    } catch (e) {
      print('Delete picking list error: $e');
      return false;
    }
  }

  // Sync data from ERP (Scrape & Save)
  Future<Map<String, dynamic>?> syncErpStockData({
    String? date,
    String? warehouse,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/erp/sync'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'date': date, 'warehouse': warehouse}),
          )
          .timeout(const Duration(minutes: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('Sync ERP stock data error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> uploadErpExcel(
    File file,
    String warehouse,
  ) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/erp/import'),
      );
      request.fields['warehouse'] = warehouse;
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
          contentType: MediaType(
            'application',
            'vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ),
      );

      var response = await request.send();
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        return jsonDecode(respStr);
      }
    } catch (e) {
      print('Upload ERP Excel error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> uploadDynamicColumnsExcel(File file) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/erp/import-dynamic'),
      );
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
          contentType: MediaType(
            'application',
            'vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ),
      );

      print('Uploading Dynamic Excel...');
      var response = await request.send();
      final respStr = await response.stream.bytesToString();
      print('Response: ${response.statusCode} - $respStr');

      if (response.statusCode == 200) {
        return jsonDecode(respStr);
      }
    } catch (e) {
      print('Upload Dynamic Excel error: $e');
    }
    return null;
  }

  Future<bool> updateErpPackingNote(
    String sku,
    String note, {
    String? warehouse,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/erp/update-packing'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'sku': sku, 'note': note, 'warehouse': warehouse}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Update packing note error: $e');
    }
    return false;
  }

  Future<bool> updateErpDiffNn(
    String sku,
    String diffNn, {
    String? warehouse,
    List<String>? mergedSkus,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/erp/update-diff-nn'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sku': sku,
          'diffNn': diffNn,
          'warehouse': warehouse,
          'mergedSkus': mergedSkus ?? [],
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Update diff_nn error: $e');
    }
    return false;
  }

  // Audit History APIs
  Future<List<dynamic>> getAuditHistory({String? auditor, String? sku}) async {
    try {
      var uri = Uri.parse('$baseUrl/audit/history');
      final params = <String, String>{};
      if (auditor != null && auditor.isNotEmpty) params['auditor'] = auditor;
      if (sku != null && sku.isNotEmpty) params['sku'] = sku;

      uri = uri.replace(queryParameters: params.isEmpty ? null : params);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('Get audit history error: $e');
    }
    return [];
  }

  Future<bool> updateAuditRecord(int id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/audit/history/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Update audit record error: $e');
    }
    return false;
  }

  Future<bool> deleteAuditRecord(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/audit/history/$id'),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Delete audit record error: $e');
    }
    return false;
  }

  Future<bool> deleteMultipleAuditRecords(List<int> ids) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/audit/history/delete-multiple'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ids': ids}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Delete multiple audit records error: $e');
    }
    return false;
  }

  Future<bool> deleteAllAuditRecords() async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/audit/history/all'),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Delete all audit records error: $e');
    }
    return false;
  }

  // Get data from Local DB
  Future<List<String>> getErpWarehouses() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/erp/warehouses'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => e.toString()).toList();
      }
    } catch (e) {
      print('Get ERP warehouses error: $e');
    }
    return [];
  }

  Future<List<dynamic>> getErpStockFromDb({String? warehouse}) async {
    try {
      final query = 'warehouse=${warehouse ?? ''}';
      final response = await http.get(Uri.parse('$baseUrl/erp/stock?$query'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('Get ERP stock from DB error: $e');
    }
    return [];
  }

  // Update Stock Audit (KK columns)
  Future<Map<String, dynamic>?> updateStockAudit({
    required String sku,
    required double quantity,
    String? warehouse,
    String? auditor,
    int? packagingStandard,
    int? horRows,
    int? verRows,
    int? evenRows,
    int? oddRows,
    int? individualBags,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/erp/audit-update'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sku': sku,
          'quantity': quantity,
          'warehouse': warehouse,
          'auditor': auditor,
          'packagingStandard': packagingStandard,
          'horRows': horRows,
          'verRows': verRows,
          'evenRows': evenRows,
          'oddRows': oddRows,
          'individualBags': individualBags,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Audit update failed: ${response.body}');
      }
    } catch (e) {
      print('Update stock audit error: $e');
    }
    return null;
  }

  Future<bool> updateAuditHistoryItem(
    int id,
    double newQty,
    String note,
  ) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/stock-audit/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'totalResult': newQty, 'note': note}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Update audit history item error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> fetchDetailedErpStock(
    String sku, {
    String? warehouse,
  }) async {
    try {
      final query = warehouse != null ? '?warehouse=$warehouse' : '';
      final response = await http.get(
        Uri.parse('$baseUrl/erp/stock/$sku/all$query'),
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return body['success'] == true ? body['data'] : null;
      }
    } catch (e) {
      print('Fetch detailed stock error: $e');
    }
    return null;
  }

  Future<bool> updateAuditSlots(
    int? id,
    Map<String, dynamic> slots, {
    String? auditor,
    String? sku,
    String? warehouse,
  }) async {
    try {
      final body = {
        'id': id,
        'slots': slots,
        'auditor': auditor,
        'sku': sku,
        'warehouse': warehouse,
      };
      final response = await http.post(
        Uri.parse('$baseUrl/erp/audit-update-slots'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Update audit slots error: $e');
      return false;
    }
  }

  Future<bool> resolveNotification(
    int id,
    String user,
    String resultText,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/notifications/$id/resolve'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user': user, 'resultText': resultText}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Resolve notification error: $e');
      return false;
    }
  }

  Future<bool> markNotificationRead(String id, String user) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/notifications/$id/read'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user': user}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Mark notification read error: $e');
      return false;
    }
  }

  Future<List<dynamic>> getNotifications({String? user}) async {
    try {
      final query = user != null ? '?user=$user' : '';
      final response = await http.get(
        Uri.parse('$baseUrl/notifications$query'),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
    } catch (e) {
      print('Get notifications error: $e');
    }
    return [];
  }

  Future<bool> hideNotifications(List<int> ids, String user) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/notifications/hide'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ids': ids, 'user': user}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Hide notifications error: $e');
      return false;
    }
  }

  Future<bool> deleteNotificationsGlobal(List<int> ids) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/notifications/delete-multiple'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ids': ids}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Delete notifications global error: $e');
      return false;
    }
  }

  Future<bool> sendNotification({
    required String message,
    String type = 'INFO',
    String? sender,
    Map<String, dynamic>? metadata,
  }) async {
    final url = Uri.parse('$baseUrl/notify');
    try {
      print('[ApiService] Sending notification to: $url');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': message,
          'type': type,
          'sender': sender,
          'metadata': metadata,
        }),
      );
      print('[ApiService] Response: ${response.statusCode} - ${response.body}');
      return response.statusCode == 200;
    } catch (e) {
      print('[ApiService] Send notification error at $url: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> getSystemSettings() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/settings'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('Get system settings error: $e');
    }
    return {};
  }

  Future<bool> updateSystemSetting(String key, String value) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/settings'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'key': key, 'value': value}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Update system setting error: $e');
      return false;
    }
  }
}

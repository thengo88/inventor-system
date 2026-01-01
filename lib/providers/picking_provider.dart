import 'package:flutter/material.dart';
import '../models/picking_list.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

class PickingProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  AuthProvider? _authProvider;

  List<PickingList> _pickingLists = [];
  bool _isLoading = false;

  void updateAuth(AuthProvider auth) {
    _authProvider = auth;
  }

  List<PickingList> get pickingLists => _pickingLists;
  bool get isLoading => _isLoading;
  ApiService get apiService => _apiService;

  Future<void> fetchPickingLists({
    String? recs,
    String? typs,
    String? ps,
    String? oprs,
    String? tr,
    String? gate,
    String? line,
    String? zone,
    String? box,
    bool silent = false,
  }) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }

    // If explicit filters are provided, use them. Otherwise use auth provider filters for non-admins.
    if (recs != null ||
        typs != null ||
        ps != null ||
        oprs != null ||
        tr != null ||
        gate != null ||
        line != null ||
        zone != null ||
        box != null) {
      _pickingLists = await _apiService.getPickingLists(
        username: _authProvider?.currentUser?.username,
        recs: recs,
        typs: typs,
        ps: ps,
        oprs: oprs,
        tr: tr,
        gate: gate,
        line: line,
        zone: zone,
        box: box,
        isFiltered: true,
      );
    } else if (_authProvider != null &&
        !_authProvider!.isAdmin &&
        _authProvider!.currentUser != null) {
      final user = _authProvider!.currentUser!;
      _pickingLists = await _apiService.getPickingLists(
        username: user.username,
        recs: user.assignedRecs,
        typs: user.assignedTyps,
        ps: user.assignedPs,
        oprs: user.assignedOprs,
        tr: user.assignedTr,
        gate: user.assignedGate,
        line: user.assignedLine,
        zone: user.assignedZone,
        box: user.assignedBox,
        isFiltered: true,
      );
    } else {
      _pickingLists = await _apiService.getPickingLists(
        username: _authProvider?.currentUser?.username,
      );
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> createPicking(
    String orderNum,
    String customer,
    List<Map<String, dynamic>> items,
  ) async {
    final success = await _apiService.createPickingList(
      orderNum,
      customer,
      items,
    );
    if (success) {
      await _authProvider?.logAction('Tạo đơn soạn hàng', 'Đơn: $orderNum');
      await fetchPickingLists();
    }
    return success;
  }

  Future<List<String>?> getExcelHeaders(
    dynamic file, {
    String? selectedSheet,
  }) async {
    return await _apiService.getExcelHeaders(
      file,
      selectedSheet: selectedSheet,
    );
  }

  Future<Map<String, dynamic>?> importFromExcel(
    String orderNum,
    String customer,
    dynamic file, {
    String? selectedSheet,
    String? selectedDate,
    Map<String, String>? columnMapping,
  }) async {
    final result = await _apiService.importExcelPickingList(
      orderNum,
      customer,
      file,
      selectedSheet: selectedSheet,
      selectedDate: selectedDate,
      columnMapping: columnMapping,
    );
    if (result != null) {
      final actualOrderNum = result['orderNumber'] ?? orderNum;
      await _authProvider?.logAction(
        'Nhập đơn từ Excel',
        'Đơn: $actualOrderNum',
      );
      await fetchPickingLists();
    }
    return result;
  }

  Future<void> updateItemQuantity(
    PickingItem item,
    int quantityScanned,
    String orderNum,
  ) async {
    final username = _authProvider?.currentUser?.username ?? 'Unknown';
    final success = await _apiService.updatePickedQuantity(
      item.id!,
      item.quantityPicked,
      username,
    );
    if (success && _authProvider != null) {
      await _apiService.addPickingHistory({
        'username': _authProvider!.currentUser?.username ?? 'Unknown',
        'orderNumber': orderNum,
        'sku': item.sku,
        'productName': item.productName,
        'quantityPicked': quantityScanned,
        'rec_hh': item.rec_hh ?? '',
        'odr_typ': item.odr_typ ?? '',
        'ps_cd': item.ps_cd ?? '',
        'rec_opr': item.rec_opr ?? '',
        'zone': item.zone ?? '',
        'tr_no': item.tr_no ?? '',
        'gate': item.gate ?? '',
        'line': item.line ?? '',
        'box': item.box ?? '',
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<List<Map<String, dynamic>>> getPickingHistory() async {
    return await _apiService.getPickingHistory();
  }

  Future<bool> clearHistory() async {
    return await _apiService.clearPickingHistory();
  }

  Future<void> completePicking(int listId, String orderNum) async {
    final success = await _apiService.updatePickingStatus(listId, 'completed');
    if (success) {
      await _authProvider?.logAction('Hoàn thành soạn hàng', 'Đơn: $orderNum');
      await fetchPickingLists();
    }
  }

  Future<bool> deletePicking(int id, String orderNum) async {
    final success = await _apiService.deletePickingList(id);
    if (success) {
      await _authProvider?.logAction('Xóa đơn soạn hàng', 'Đơn: $orderNum');
      await fetchPickingLists();
    }
    return success;
  }
}

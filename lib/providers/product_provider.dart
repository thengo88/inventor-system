import 'dart:io';
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

class ProductProvider with ChangeNotifier {
  List<Product> _products = [];
  final ApiService _apiService = ApiService();
  AuthProvider? _authProvider;
  Map<String, double> _erpStock = {};

  void updateAuth(AuthProvider auth) {
    _authProvider = auth;
  }

  Map<String, double> get erpStock => _erpStock;

  Future<void> fetchErpStock() async {
    try {
      final data = await _apiService.getErpStockFromDb();
      Map<String, double> qtys = {};
      for (var item in data) {
        final sku = item['sku']?.toString() ?? '';
        final q = double.tryParse(item['quantity']?.toString() ?? '0') ?? 0;
        qtys[sku] = (qtys[sku] ?? 0) + q;
      }
      _erpStock = qtys;
      notifyListeners();
    } catch (e) {
      debugPrint('Fetch ERP stock error: $e');
    }
  }

  double getCurrentStock(Product p, String source) {
    if (source == 'anc-wms') {
      return p.stock;
    } else {
      return _erpStock[p.sku] ?? 0;
    }
  }

  List<Product> get products => _products;

  Future<void> fetchProducts() async {
    _products = await _apiService.getProducts();
    await fetchErpStock();
    notifyListeners();
  }

  Future<bool> addProduct(Product product, File? image, File? image2) async {
    final success = await _apiService.addProduct(product, image, image2);
    if (success) {
      await _authProvider?.logAction(
        'Thêm sản phẩm',
        'Đã thêm: ${product.name} (Server)',
      );
      await fetchProducts();
    }
    return success;
  }

  Future<bool> updateProduct(Product product, File? image, File? image2) async {
    final success = await _apiService.updateProduct(product, image, image2);
    if (success) {
      await _authProvider?.logAction(
        'Sửa sản phẩm',
        'Đã sửa: ${product.name} (Server)',
      );
      await fetchProducts();
    }
    return success;
  }

  Future<bool> updateStock(
    Product product,
    double addedQty,
    bool isAdditive,
  ) async {
    final success = await _apiService.updateProduct(product, null, null);
    if (success) {
      final action = isAdditive ? 'Nhập kho' : 'Cập nhật tồn';
      final detail = isAdditive
          ? 'Đã nhập thêm $addedQty cho ${product.sku}. Tổng: ${product.stock}'
          : 'Đã đặt tồn kho ${product.sku} thành ${product.stock}';

      await _authProvider?.logAction(action, detail);
      await fetchProducts();
    }
    return success;
  }

  Future<bool> deleteProduct(int id) async {
    final product = _products.firstWhere((p) => p.id == id);
    final success = await _apiService.deleteProduct(id);
    if (success) {
      await _authProvider?.logAction(
        'Xóa sản phẩm',
        'Đã xóa: ${product.name} (Server)',
      );
      await fetchProducts();
    }
    return success;
  }

  Future<Product?> scanProduct(String sku) async {
    final product = await _apiService.getProductBySku(sku);
    if (product != null) {
      await _authProvider?.logAction(
        'Quét mã',
        'Đã quét thành công: ${product.name}',
      );
    } else {
      await _authProvider?.logAction(
        'Quét mã thất bại',
        'SKU: $sku không tồn tại trên Server',
      );
    }
    return product;
  }

  String getFullImageUrl(String? path) {
    if (path == null || path.isEmpty) return "";
    if (path.startsWith('http')) return path;
    return _apiService.uploadUrl + path;
  }

  String getServerIpAddress() {
    // Extract IP from baseUrl for UI display
    return _apiService.baseUrl
        .replaceFirst('http://', '')
        .replaceFirst(':3000/api', '');
  }
}

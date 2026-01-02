import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:convert';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:audioplayers/audioplayers.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../providers/product_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/settings_provider.dart' as sp;
import '../widgets/global_data_sync.dart';
import 'admin/system_screen.dart';
import 'admin/erp_data_tab.dart';

// Import optimized operations for concurrent-safe updates
import '../mixins/optimized_operations.dart';

class StockAuditScreen extends StatefulWidget {
  const StockAuditScreen({super.key});

  @override
  State<StockAuditScreen> createState() => _StockAuditScreenState();
}

class _StockAuditScreenState extends State<StockAuditScreen>
    with
        WidgetsBindingObserver,
        SingleTickerProviderStateMixin,
        OptimizedOperations {
  final AudioPlayer _audioPlayer = AudioPlayer();
  late TabController _tabController;

  // Scanner & Calculator Controllers
  final TextEditingController _warehouseController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _pcsPerBagController = TextEditingController();
  final TextEditingController _ngangController = TextEditingController();
  final TextEditingController _docController = TextEditingController();
  final TextEditingController _chanController = TextEditingController();
  final TextEditingController _leController = TextEditingController();
  final TextEditingController _pcsLeController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _totalQtyController = TextEditingController();

  final FocusNode _codeFocus = FocusNode();
  final FocusNode _warehouseFocus = FocusNode();

  // Status State
  String _statusMessage = "Sẵn sàng";
  Color _statusColor = Colors.black87;
  bool _isLoading = false;
  bool _isLoadingData = false;
  List<dynamic> _erpStockList = [];

  // History State
  List<dynamic> _historyList = [];
  List<dynamic> _filteredHistory = [];
  final TextEditingController _filterCodeController = TextEditingController();
  final TextEditingController _filterUserController = TextEditingController();
  bool _isLoadingHistory = false;

  // Notification State
  // Removed _notifications and _socket related states, now managed by NotificationProvider
  final Set<int> _selectedNotificationIndices = {};
  bool _isSelectionMode = false;
  String? _currentResolvingNotificationId;
  StreamSubscription? _refreshSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // Calculator Listeners
    _pcsPerBagController.addListener(_calculateTotal);
    _ngangController.addListener(_calculateTotal);
    _docController.addListener(_calculateTotal);
    _chanController.addListener(_calculateTotal);
    _leController.addListener(_calculateTotal);
    _pcsLeController.addListener(_calculateTotal);

    // History Filters
    _filterCodeController.addListener(_filterHistoryLocal);
    _filterUserController.addListener(_filterHistoryLocal);

    _loadInitialData();
    WidgetsBinding.instance.addObserver(this);
    _refreshSub = GlobalDataSync.onRefresh.listen((category) {
      // Use contains to match 'stock-audit' or 'audit'
      if (mounted &&
          (category.contains('audit') ||
              category.contains('erp') ||
              category == 'general')) {
        _loadInitialData(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _refreshSub?.cancel();
    // WakelockPlus.disable(); // Removed to keep screen on globally as requested
    // _socket?.disconnect(); // Removed
    _tabController.dispose();
    _warehouseController.dispose();
    _codeController.dispose();
    _pcsPerBagController.dispose();
    _ngangController.dispose();
    _docController.dispose();
    _chanController.dispose();
    _leController.dispose();
    _pcsLeController.dispose();
    _totalQtyController.dispose();
    _locationController.dispose();
    _filterCodeController.dispose();
    _filterUserController.dispose();
    _codeFocus.dispose();
    _warehouseFocus.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _loadInitialData({bool silent = false}) {
    _loadErpData(silent: silent);
    _fetchHistory(silent: silent);
    if (!silent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final user = context.read<AuthProvider>().currentUser?.username;
        context.read<NotificationProvider>().init(user);
      });
    }
  }

  Future<void> _loadErpData({bool silent = false}) async {
    if (!silent) setState(() => _isLoadingData = true);
    try {
      final data = await ApiService().getErpStockFromDb(
        warehouse: _warehouseController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _erpStockList = data;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  void _calculateTotal() {
    double n = double.tryParse(_ngangController.text) ?? 0;
    double d = double.tryParse(_docController.text) ?? 0;
    double c = double.tryParse(_chanController.text) ?? 0;
    double l = double.tryParse(_leController.text) ?? 0;
    double p = double.tryParse(_pcsPerBagController.text) ?? 0;
    double pl = double.tryParse(_pcsLeController.text) ?? 0;

    double total = ((n * d * c) + l) * p + pl;
    _totalQtyController.text = total.toStringAsFixed(0);
    setState(() {});
  }

  void _onSkuSelected(String sku) {
    if (sku.isEmpty) return;

    final normalizedSku = sku.replaceAll('-', '').toLowerCase();

    // --- IMMEDIATE SKU VALIDATION ---
    final source = context.read<sp.SettingsProvider>().stockSource;
    bool exists = false;

    if (source == 'anc-wms') {
      exists = context.read<ProductProvider>().products.any(
        (p) =>
            p.sku.replaceAll('-', '').toLowerCase() == normalizedSku ||
            (p.skuPlain ?? '').toLowerCase() == normalizedSku,
      );
    } else {
      exists = _erpStockList.any(
        (e) =>
            (e['sku'] ?? '').toString().replaceAll('-', '').toLowerCase() ==
                normalizedSku ||
            (e['sku_plain'] ?? '').toString().toLowerCase() == normalizedSku,
      );
    }

    if (!exists) {
      _showSnack(
        "Mã số không tồn tại trong hệ thống ${source == 'anc-wms' ? 'ANC-WMS' : 'ERP'} vui lòng kiểm tra và thực hiện lại",
        Colors.red,
      );
      _audioPlayer.play(AssetSource('sounds/error.wav'));
      _codeController.clear(); // Clear the invalid input
      return;
    }

    // --- RESOLVE TO PRIMARY (HYPHENATED) SKU ---
    String primarySku = sku;
    if (source == 'anc-wms') {
      try {
        final p = context.read<ProductProvider>().products.firstWhere(
          (p) =>
              p.sku.replaceAll('-', '').toLowerCase() == normalizedSku ||
              (p.skuPlain ?? '').toLowerCase() == normalizedSku,
        );
        primarySku = p.sku;
      } catch (_) {}
    } else {
      final erpItem = _erpStockList.firstWhere(
        (e) =>
            (e['sku'] ?? '').toString().replaceAll('-', '').toLowerCase() ==
                normalizedSku ||
            (e['sku_plain'] ?? '').toString().toLowerCase() == normalizedSku,
        orElse: () => {},
      );
      if (erpItem.isNotEmpty) {
        primarySku = erpItem['sku'].toString();
      }
    }

    _codeController.text = primarySku;

    // Auto-fill Warehouse from ERP Data if not set
    if (_warehouseController.text.isEmpty) {
      final erpItem = _erpStockList.firstWhere(
        (e) =>
            (e['sku'] ?? '').toString().replaceAll('-', '').toLowerCase() ==
                normalizedSku ||
            (e['sku_plain'] ?? '').toString().toLowerCase() == normalizedSku,
        orElse: () => {},
      );
      if (erpItem.isNotEmpty && erpItem['warehouse'] != null) {
        _warehouseController.text = erpItem['warehouse'].toString();
        _loadErpData();
      }
    }

    // Check in local ProductProvider for packaging info (Pcs/Bag)
    try {
      final products = context.read<ProductProvider>().products;
      if (products.isNotEmpty) {
        final productIndex = products.indexWhere(
          (p) =>
              p.sku.replaceAll('-', '').toLowerCase() == normalizedSku ||
              (p.skuPlain ?? '').toLowerCase() == normalizedSku,
        );

        if (productIndex != -1) {
          final pkg = products[productIndex].packagingStandard;
          final match = RegExp(r'(\d+)').firstMatch(pkg);
          if (match != null) _pcsPerBagController.text = match.group(0)!;
        }
      }
    } catch (e) {}

    _calculateTotal();
    FocusScope.of(context).unfocus(); // Ẩn bàn phím sau khi chọn mã số
  }

  Future<void> _submitData() async {
    final code = _codeController.text.trim();
    final valueStr = _totalQtyController.text;
    final warehouse = _warehouseController.text.trim();
    final user =
        context.read<AuthProvider>().currentUser?.username ?? 'Unknown';

    if (code.isEmpty || valueStr.isEmpty || valueStr == '0') {
      _showSnack("Vui lòng nhập Mã SP và Số lượng", Colors.red);
      return;
    }

    // --- FINAL SKU VALIDATION & RESOLUTION ---
    final normalizedCode = code.replaceAll('-', '').toLowerCase();
    final source = context.read<sp.SettingsProvider>().stockSource;
    bool exists = false;
    String primarySku = code;

    if (source == 'anc-wms') {
      try {
        final p = context.read<ProductProvider>().products.firstWhere(
          (p) =>
              p.sku.replaceAll('-', '').toLowerCase() == normalizedCode ||
              (p.skuPlain ?? '').toLowerCase() == normalizedCode,
        );
        exists = true;
        primarySku = p.sku;
      } catch (_) {
        exists = false;
      }
    } else {
      final erpItem = _erpStockList.firstWhere(
        (e) =>
            (e['sku'] ?? '').toString().replaceAll('-', '').toLowerCase() ==
                normalizedCode ||
            (e['sku_plain'] ?? '').toString().toLowerCase() == normalizedCode,
        orElse: () => {},
      );
      if (erpItem.isNotEmpty) {
        exists = true;
        primarySku = erpItem['sku'].toString();
      }
    }

    if (!exists) {
      _showSnack(
        "Mã số không tồn tại trong hệ thống ${source == 'anc-wms' ? 'ANC-WMS' : 'ERP'} vui lòng kiểm tra và thực hiện lại",
        Colors.red,
      );
      _audioPlayer.play(AssetSource('sounds/error.wav'));
      return;
    }

    // ----------------------------

    setState(() => _isLoading = true);

    try {
      // Use safe method with optimistic locking
      final success = await safeUpdateStockAudit(
        apiService: ApiService(),
        sku: code,
        warehouse: warehouse.isEmpty ? 'Default' : warehouse,
        updates: {
          'packagingStandard': int.tryParse(_pcsPerBagController.text) ?? 0,
          'horRows': int.tryParse(_ngangController.text) ?? 0,
          'verRows': int.tryParse(_docController.text) ?? 0,
          'evenRows': int.tryParse(_chanController.text) ?? 0,
          'oddRows': int.tryParse(_leController.text) ?? 0,
          'individualBags': int.tryParse(_pcsLeController.text) ?? 0,
          'totalResult': double.tryParse(valueStr) ?? 0,
          'location': _locationController.text.trim(),
        },
        auditor: user,
        showSnackbar: true,
      );

      if (success) {
        _audioPlayer.play(AssetSource('sounds/beep.wav'));
        // Force refresh global product data locally immediately
        await context.read<ProductProvider>().fetchProducts();
        _resetCalculator();
        _fetchHistory();
        FocusScope.of(context).unfocus(); // Ẩn bàn phím sau khi ghi hệ thống
        _codeFocus.requestFocus();
      }
      // If not successful, conflict message already shown by mixin
    } catch (e) {
      _showSnack("Lỗi: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _resetCalculator() {
    _codeController.clear();
    _ngangController.clear();
    _docController.clear();
    _chanController.clear();
    _leController.clear();
    _pcsLeController.clear();
    _locationController.clear();
    _totalQtyController.text = "0";
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
    setState(() {
      _statusMessage = msg;
      _statusColor = color;
    });
  }

  // --- Socket.IO & Notifications ---
  // Removed _connectSocket and _fetchNotifications, now handled by NotificationProvider

  Future<bool> _markNotificationRead(String id) async {
    final user = context.read<AuthProvider>().currentUser?.username;
    if (user == null) return false;
    try {
      final success = await context.read<NotificationProvider>().markAsRead(id);
      if (!success) {
        final notification = context
            .read<NotificationProvider>()
            .notifications
            .firstWhere((n) => n['id'].toString() == id, orElse: () => null);
        if (notification != null &&
            (notification['readBy'] as List?)?.isNotEmpty == true) {
          _showSnack(
            "Thông báo này đã được nhận bởi người khác",
            Colors.orange,
          );
        }
      }
      return success;
    } catch (e) {
      debugPrint("Mark read error: $e");
    }
    return false;
  }

  Future<void> _handleCheckDiscrepancy(String code, String? notifId) async {
    if (notifId != null) {
      bool success = await _markNotificationRead(notifId);
      if (!success) return;

      setState(() {
        _currentResolvingNotificationId = notifId;
      });
    }

    setState(() {
      _filterCodeController.text = code;
      _tabController.animateTo(1);
    });

    _fetchHistory().then((_) {
      _showDiscrepancyDialog(code);
    });
  }

  Future<void> _handleReAuditRequest(
    String sku,
    String? warehouse,
    String notifId,
  ) async {
    bool success = await _markNotificationRead(notifId);
    if (!success) return;

    setState(() => _isLoading = true);
    try {
      final itemData = await ApiService().fetchDetailedErpStock(
        sku,
        warehouse: warehouse,
      );
      if (itemData != null) {
        _showReAuditEditDialog(itemData, notifId);
      } else {
        // Fallback: Check checking ANC-WMS data (ProductProvider)
        try {
          final products = context.read<ProductProvider>().products;
          final wmsItem = products.where((p) => p.sku == sku).firstOrNull;

          if (wmsItem != null) {
            final Map<String, dynamic> virtualItem = {
              'id': null,
              'sku': wmsItem.sku,
              'warehouse': wmsItem.layoutPosition,
              'quantity': '0', // ERP Qty is unknown/0 since it's not in ERP yet
              'kk1': '0', 'kk2': '0', 'kk3': '0', 'kk4': '0', 'kk5': '0',
              'kk6': '0', 'kk7': '0', 'kk8': '0', 'kk9': '0', 'kk10': '0',
            };
            _showReAuditEditDialog(virtualItem, notifId);
            return;
          }
        } catch (e) {
          debugPrint("WMS fallback check error: $e");
        }
        _showSnack("Không tìm thấy dữ liệu cho mã $sku", Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showReAuditEditDialog(Map<String, dynamic> item, String notifId) {
    final Map<String, TextEditingController> controllers = {};
    for (int i = 1; i <= 10; i++) {
      controllers['kk$i'] = TextEditingController(
        text: (item['kk$i'] ?? '0').toString(),
      );
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Chỉnh sửa Kiểm kê: ${item['sku']}"),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "ERP Qty: ${item['quantity']}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Divider(),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: List.generate(10, (index) {
                    int k = index + 1;
                    return SizedBox(
                      width: 80,
                      child: TextField(
                        controller: controllers['kk$k'],
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: "KK$k",
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Hủy"),
          ),
          ElevatedButton(
            onPressed: () async {
              final Map<String, dynamic> newSlots = {};
              controllers.forEach((k, ctrl) => newSlots[k] = ctrl.text);

              final user = context.read<AuthProvider>().currentUser?.username;
              final ok = await ApiService().updateAuditSlots(
                item['id'],
                newSlots,
                auditor: user,
                sku: item['sku'],
                warehouse: item['warehouse'],
              );

              if (ok) {
                await context.read<NotificationProvider>().resolveNotification(
                  int.tryParse(notifId) ?? 0,
                  user ?? 'System',
                  'Đã kiểm lại và cập nhật số lượng',
                );
                // Force global refresh
                if (mounted) {
                  await context.read<ProductProvider>().fetchProducts();
                }
                if (mounted) {
                  Navigator.pop(ctx);
                  _showSnack(
                    "Đã cập nhật dữ liệu mã ${item['sku']}",
                    Colors.green,
                  );
                  _loadInitialData();
                }
              }
            },
            child: const Text("Cập nhật"),
          ),
        ],
      ),
    );
  }

  void _showDiscrepancyDialog(String code) {
    final items = _historyList
        .where((item) => (item['sku'] ?? '').toString() == code)
        .toList();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Kiểm tra: $code"),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: items.isEmpty
                ? const Center(child: Text("Không có dữ liệu kiểm kê"))
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          title: Text(
                            "User: ${item['auditor']}",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            "Time: ${item['timestamp']?.substring(11, 19)}",
                          ),
                          trailing: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              Text(
                                "${item['totalResult']}",
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.blue,
                                ),
                                onPressed: () {
                                  Navigator.pop(context);
                                  _showEditHistoryDialog(item);
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _currentResolvingNotificationId = null;
                Navigator.pop(context);
              },
              child: const Text("Đóng"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteSelectedNotifications() async {
    final user = context.read<AuthProvider>().currentUser?.username;
    if (user == null) return;

    final isAdmin = context.read<AuthProvider>().isAdmin;
    if (isAdmin) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Xóa thông báo"),
          content: const Text("Bạn muốn xóa thông báo này như thế nào?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Hủy"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Chỉ ẩn cho tôi"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text(
                "Xóa cho tất cả mọi người",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );

      if (confirm == null) return;
      if (confirm) {
        final ids = _getSelectedIds();
        if (ids.isNotEmpty) {
          await context.read<NotificationProvider>().deleteNotificationsGlobal(
            ids,
          );
        }
        setState(() {
          _selectedNotificationIndices.clear();
          _isSelectionMode = false;
        });
        return;
      }
    }

    final ids = _getSelectedIds();
    if (ids.isNotEmpty) {
      await context.read<NotificationProvider>().deleteNotifications(ids);
    }

    setState(() {
      _selectedNotificationIndices.clear();
      _isSelectionMode = false;
    });
  }

  List<int> _getSelectedIds() {
    final notifications = context.read<NotificationProvider>().notifications;
    final ids = <int>[];
    for (final index in _selectedNotificationIndices) {
      if (index < notifications.length) {
        final item = notifications[index];
        if (item['id'] != null) {
          final id = int.tryParse(item['id'].toString());
          if (id != null) ids.add(id);
        }
      }
    }
    return ids;
  }

  // --- History ---
  Future<void> _fetchHistory({bool silent = false}) async {
    if (!silent) setState(() => _isLoadingHistory = true);
    try {
      final history = await ApiService().getAuditHistory();
      if (mounted) {
        setState(() {
          _historyList = history;
          _filteredHistory = history;
        });
        _filterHistoryLocal();
      }
    } finally {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  void _filterHistoryLocal() {
    final code = _filterCodeController.text.toLowerCase();
    final user = _filterUserController.text.toLowerCase();
    setState(() {
      _filteredHistory = _historyList.where((item) {
        final iCode = (item['sku'] ?? '').toString().toLowerCase();
        final iCodePlain = (item['sku_plain'] ?? '').toString().toLowerCase();
        final iUser = (item['auditor'] ?? '').toString().toLowerCase();
        return (iCode.contains(code) || iCodePlain.contains(code)) &&
            iUser.contains(user);
      }).toList();
    });
  }

  // --- Scanner ---
  void _openScanner() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SimpleScannerPage()),
    );
    if (result != null && result is String) {
      String? processed = result.trim();
      if (processed.isNotEmpty) {
        FocusScope.of(
          context,
        ).unfocus(); // Ẩn bàn phím sau khi quét QR thành công
      }

      // Xử lý định dạng: A00BB12206-K1B-T001;100
      if (processed.contains(';')) {
        List<String> parts = processed.split(';');
        String sku = parts[0].trim();
        String pcsPerBag = parts.length > 1 ? parts[1].trim() : "";

        _onSkuSelected(sku);
        if (pcsPerBag.isNotEmpty) {
          _pcsPerBagController.text = pcsPerBag;
          _calculateTotal();
        }
        return;
      }

      if (processed.contains(':')) {
        List<String> parts = processed.split(':');
        if (parts.length > 1) processed = parts[1].trim();
      }
      _onSkuSelected(processed);
    }
  }

  @override
  Widget build(BuildContext context) {
    WakelockPlus.enable(); // Force enable to bypass any screen-specific sleep settings
    final double zoom = context.watch<sp.SettingsProvider>().zoomLevel;
    final double tabHeight = 82.0 * (zoom > 1.0 ? zoom : 1.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Kiểm kê kho',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Theme.of(context).primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadInitialData,
          ),
          if (context.read<AuthProvider>().isAdmin)
            PopupMenuButton<String>(
              icon: const Icon(Icons.menu, color: Colors.white),
              onSelected: (value) {
                if (value == 'config') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SystemScreen()),
                  );
                } else if (value == 'erp') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('Dữ liệu ERP')),
                        body: const ErpDataTab(),
                      ),
                    ),
                  );
                }
              },
              itemBuilder: (BuildContext context) {
                return [
                  const PopupMenuItem<String>(
                    value: 'config',
                    child: Row(
                      children: [
                        Icon(Icons.settings, color: Colors.blueGrey),
                        SizedBox(width: 8),
                        Text('Cấu hình'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'erp',
                    child: Row(
                      children: [
                        Icon(Icons.storage, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('Dữ liệu ERP'),
                      ],
                    ),
                  ),
                ];
              },
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildScannerTab(),
          _buildHistoryTab(),
          _buildNotificationTab(),
        ],
      ),
      bottomNavigationBar: Material(
        color: Theme.of(context).primaryColor,
        elevation: 10,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TabBar(
                controller: _tabController,
                isScrollable: false, // Chia đều sắp xếp cân đối
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white.withOpacity(0.6),
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                tabs: [
                  Tab(
                    icon: const Icon(Icons.calculate, size: 28),
                    text: "Máy tính",
                    height: tabHeight,
                  ),
                  Tab(
                    icon: const Icon(Icons.history, size: 28),
                    text: "Lịch sử",
                    height: tabHeight,
                  ),
                  Consumer<NotificationProvider>(
                    builder: (ctx, nav, _) => Tab(
                      icon: Badge(
                        label: Text("${nav.unreadCount}"),
                        isLabelVisible: nav.unreadCount > 0,
                        backgroundColor: Colors.redAccent,
                        child: const Icon(Icons.notifications, size: 28),
                      ),
                      text: "Thông báo",
                      height: tabHeight,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              onPressed: _openScanner,
              backgroundColor: Colors.blue,
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_scanner, size: 24, color: Colors.white),
                  Text(
                    "QUÉT",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget _buildScannerTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Warehouse Selector - Hidden per user request for auto-detection
          // LayoutBuilder(
          //   builder: (context, constraints) {
          //     final zoom = context.watch<sp.SettingsProvider>().zoomLevel;
          //     return RawAutocomplete<String>(
          //       focusNode: _warehouseFocus,
          //       textEditingController: _warehouseController,
          //       optionsBuilder: (textValue) {
          //         return _warehouses.where(
          //           (w) =>
          //               w.toLowerCase().contains(textValue.text.toLowerCase()),
          //         );
          //       },
          //       onSelected: (val) {
          //         _warehouseController.text = val;
          //         _loadErpData(); // Reload SKU list for this warehouse
          //       },
          //       optionsViewBuilder: (ctx, onSelected, options) {
          //         return Align(
          //           alignment: Alignment.topLeft,
          //           child: Material(
          //             elevation: 4.0,
          //             child: ConstrainedBox(
          //               constraints: BoxConstraints(maxHeight: 200 * zoom),
          //               child: SizedBox(
          //                 width: constraints.maxWidth,
          //                 child: ListView.builder(
          //                   padding: EdgeInsets.zero,
          //                   shrinkWrap: true,
          //                   itemCount: options.length,
          //                   itemBuilder: (context, index) {
          //                     final option = options.elementAt(index);
          //                     return ListTile(
          //                       title: Text(option),
          //                       onTap: () => onSelected(option),
          //                     );
          //                   },
          //                 ),
          //               ),
          //             ),
          //           ),
          //         );
          //       },
          //       fieldViewBuilder: (ctx, ctrl, focus, onSubmitted) {
          //         return TextField(
          //           controller: ctrl,
          //           focusNode: focus,
          //           style: const TextStyle(fontWeight: FontWeight.bold),
          //           decoration: const InputDecoration(
          //             labelText: "Chọn Kho (Bắt buộc)",
          //             prefixIcon: Icon(Icons.warehouse),
          //             border: OutlineInputBorder(),
          //             isDense: true,
          //           ),
          //         );
          //       },
          //     );
          //   },
          // ),
          const SizedBox(height: 0), // Use 0 height placeholder
          // Product Code & Pcs/Bag
          LayoutBuilder(
            builder: (context, constraints) {
              final zoom = context.watch<sp.SettingsProvider>().zoomLevel;
              final bool isWide = constraints.maxWidth > 500 && zoom <= 1.2;

              return Wrap(
                spacing: 8,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: isWide
                        ? (constraints.maxWidth - 8) * 0.7
                        : constraints.maxWidth,
                    child: RawAutocomplete<String>(
                      textEditingController: _codeController,
                      focusNode: _codeFocus,
                      optionsBuilder: (textValue) {
                        if (textValue.text.isEmpty)
                          return const Iterable<String>.empty();
                        final source = context
                            .read<sp.SettingsProvider>()
                            .stockSource;
                        final query = textValue.text.toLowerCase();

                        List<String> results = [];
                        if (source == 'anc-wms') {
                          results = context
                              .read<ProductProvider>()
                              .products
                              .where(
                                (p) =>
                                    p.sku.toLowerCase().contains(query) ||
                                    (p.skuPlain ?? '').toLowerCase().contains(
                                      query,
                                    ),
                              )
                              .map((p) => p.sku)
                              .toSet()
                              .toList();
                        } else {
                          results = _erpStockList
                              .where((e) {
                                final s = (e['sku'] ?? '')
                                    .toString()
                                    .toLowerCase();
                                final sp = (e['sku_plain'] ?? '')
                                    .toString()
                                    .toLowerCase();
                                return s.contains(query) || sp.contains(query);
                              })
                              .map((e) => (e['sku'] ?? '').toString().trim())
                              .toSet()
                              .toList();
                        }

                        return results.take(50);
                      },

                      onSelected: _onSkuSelected,
                      optionsViewBuilder: (ctx, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4.0,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: 200 * zoom,
                              ),
                              child: SizedBox(
                                width: isWide
                                    ? (constraints.maxWidth - 8) * 0.7
                                    : constraints.maxWidth,
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder:
                                      (BuildContext context, int index) {
                                        final String option = options.elementAt(
                                          index,
                                        );
                                        return ListTile(
                                          title: Text(option),
                                          onTap: () => onSelected(option),
                                        );
                                      },
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      fieldViewBuilder: (ctx, ctrl, focus, onSubmitted) {
                        return TextField(
                          controller: ctrl,
                          focusNode: focus,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                          onSubmitted: (v) {
                            _onSkuSelected(v);
                            FocusScope.of(context).unfocus();
                          },
                          decoration: const InputDecoration(
                            labelText: "Mã Sản Phẩm (SKU)",
                            prefixIcon: Icon(Icons.qr_code),
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: isWide
                        ? (constraints.maxWidth - 8) * 0.3
                        : constraints.maxWidth,
                    child: TextField(
                      controller: _pcsPerBagController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.blue,
                      ),
                      decoration: const InputDecoration(
                        labelText: "Pcs/Túi",
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 0),
          const SizedBox(height: 16),
          const Divider(thickness: 2),
          const Center(
            child: Text(
              "QUY CÁCH ĐẾM",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Calculation Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final settings = Provider.of<sp.SettingsProvider>(context);
              final zoom = settings.zoomLevel;
              int columns = 2; // Default for small or zoomed screens

              if (zoom <= 1.2) {
                if (constraints.maxWidth > 800)
                  columns = 5;
                else if (constraints.maxWidth > 500)
                  columns = 3;
              } else if (zoom <= 1.5) {
                if (constraints.maxWidth > 800)
                  columns = 3;
                else
                  columns = 2;
              } else {
                columns = 1; // High zoom needs full width
              }

              if (columns > 1) {
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildCalcField(
                      "Hàng Ngang",
                      _ngangController,
                      (constraints.maxWidth - (columns - 1) * 12) / columns,
                    ),
                    _buildCalcField(
                      "Hàng Dọc",
                      _docController,
                      (constraints.maxWidth - (columns - 1) * 12) / columns,
                    ),
                    _buildCalcField(
                      "Hàng Chẵn",
                      _chanController,
                      (constraints.maxWidth - (columns - 1) * 12) / columns,
                    ),
                    _buildCalcField(
                      "Hàng Lẻ",
                      _leController,
                      (constraints.maxWidth - (columns - 1) * 12) / columns,
                    ),
                    _buildCalcField(
                      "PCS Lẻ",
                      _pcsLeController,
                      (constraints.maxWidth - (columns - 1) * 12) / columns,
                    ),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _buildCalcField(
                      "Hàng Ngang",
                      _ngangController,
                      double.infinity,
                    ),
                    const SizedBox(height: 12),
                    _buildCalcField(
                      "Hàng Dọc",
                      _docController,
                      double.infinity,
                    ),
                    const SizedBox(height: 12),
                    _buildCalcField(
                      "Hàng Chẵn",
                      _chanController,
                      double.infinity,
                    ),
                    const SizedBox(height: 12),
                    _buildCalcField("Hàng Lẻ", _leController, double.infinity),
                    const SizedBox(height: 12),
                    _buildCalcField(
                      "PCS Lẻ",
                      _pcsLeController,
                      double.infinity,
                    ),
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 24),
          // Total
          Center(
            child: SizedBox(
              width: 200 * context.watch<sp.SettingsProvider>().zoomLevel,
              child: TextField(
                controller: _totalQtyController,
                readOnly: true,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 40,
                  color: Colors.red,
                ),
                decoration: const InputDecoration(
                  labelText: "TỔNG SỐ",
                  floatingLabelAlignment: FloatingLabelAlignment.center,
                  filled: true,
                  fillColor: Color(0xFFFFF0F0),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Submit Button
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _submitData,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Icon(Icons.save, size: 28),
            label: Text(
              _isLoading ? "ĐANG GỬI..." : "GHI HỆ THỐNG",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          // Status
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _statusColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _statusColor.withOpacity(0.3)),
            ),
            child: Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _statusColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildCalcField(
    String label,
    TextEditingController controller,
    double width,
  ) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12),
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: 8,
          ),
          isDense: true,
        ),
        onTap: () => controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        ),
      ),
    );
  }

  Widget _buildHistoryTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double zoom = context
                  .watch<sp.SettingsProvider>()
                  .zoomLevel;
              final bool useColumn = zoom > 1.2 || constraints.maxWidth < 450;

              if (useColumn) {
                return Column(
                  children: [
                    TextField(
                      controller: _filterCodeController,
                      decoration: const InputDecoration(
                        labelText: "Lọc Mã SP",
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _filterUserController,
                            decoration: const InputDecoration(
                              labelText: "Lọc Người kiểm",
                              prefixIcon: Icon(Icons.person),
                              isDense: true,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _fetchHistory,
                        ),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _filterCodeController,
                      decoration: const InputDecoration(
                        labelText: "Lọc Mã SP",
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _filterUserController,
                      decoration: const InputDecoration(
                        labelText: "Lọc Người kiểm",
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _fetchHistory,
                  ),
                ],
              );
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchHistory,
            child: _isLoadingHistory
                ? const Center(child: CircularProgressIndicator())
                : _filteredHistory.isEmpty
                ? const Center(child: Text("Không có dữ liệu"))
                : ListView.builder(
                    itemCount: _filteredHistory.length,
                    itemBuilder: (ctx, index) {
                      final item = _filteredHistory[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: InkWell(
                          onDoubleTap: () => _showEditHistoryDialog(item),
                          child: ListTile(
                            leading: CircleAvatar(child: Text("${index + 1}")),
                            title: Text(
                              item['sku'] ?? '???',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "${item['auditor']} | ${item['warehouse'] ?? 'N/A'} | ${item['timestamp']?.substring(0, 19).replaceFirst('T', ' ')}",
                                ),
                                if (item['note'] != null &&
                                    item['note'].toString().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Text(
                                      item['note'],
                                      style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Text(
                              "${item['totalResult']}",
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  void _showEditHistoryDialog(dynamic item) {
    final TextEditingController editCtrl = TextEditingController(
      text: item['totalResult'].toString(),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Sửa số lượng: ${item['sku']}"),
        content: TextField(
          controller: editCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: "Số lượng mới",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Hủy"),
          ),
          ElevatedButton(
            onPressed: () async {
              final newQtyStr = editCtrl.text.trim();
              if (newQtyStr.isEmpty) return;
              final newQty = double.tryParse(newQtyStr) ?? 0;
              final oldQty =
                  double.tryParse(item['totalResult'].toString()) ?? 0;

              if (newQty == oldQty) {
                Navigator.pop(ctx);
                return;
              }

              final note =
                  "Đã sửa từ ${oldQty.toStringAsFixed(0)} thành ${newQty.toStringAsFixed(0)}";
              final success = await ApiService().updateAuditHistoryItem(
                item['id'],
                newQty,
                note,
              );

              if (success) {
                Navigator.pop(ctx);
                _showSnack("Đã cập nhật số lượng thành công", Colors.green);

                // Resolve notification if in flow
                if (_currentResolvingNotificationId != null) {
                  final user =
                      context.read<AuthProvider>().currentUser?.username ??
                      'Unknown';

                  // Check Diff to determine status
                  final erpItem = _erpStockList.firstWhere(
                    (e) =>
                        (e['sku'] ?? '')
                            .toString()
                            .replaceAll('-', '')
                            .toLowerCase() ==
                        item['sku']
                            .toString()
                            .replaceAll('-', '')
                            .toLowerCase(),
                    orElse: () => {},
                  );

                  String resultText = "Đã khớp";
                  if (erpItem.isNotEmpty) {
                    resultText = "Đã kiểm lại";
                  }

                  await context
                      .read<NotificationProvider>()
                      .resolveNotification(
                        int.parse(_currentResolvingNotificationId!),
                        user,
                        resultText,
                      );
                  _currentResolvingNotificationId = null;
                }

                _fetchHistory();
              } else {
                _showSnack("Lỗi khi cập nhật dữ liệu", Colors.red);
              }
            },
            child: const Text("Cập nhật"),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationTab() {
    return Consumer<NotificationProvider>(
      builder: (ctx, nav, _) {
        final notifications = nav.notifications;
        final myName = context.read<AuthProvider>().currentUser?.username;
        if (notifications.isEmpty) {
          return const Center(child: Text("Không có thông báo mới"));
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (_isSelectionMode) ...[
                    Text(
                      "Đã chọn: ${_selectedNotificationIndices.length}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            _isSelectionMode = false;
                            _selectedNotificationIndices.clear();
                          }),
                          child: const Text("Hủy"),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          label: const Text("Xóa"),
                          onPressed: _deleteSelectedNotifications,
                        ),
                      ],
                    ),
                  ] else ...[
                    const Text(
                      "Nhật ký thông báo",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.delete_sweep),
                      label: const Text("Xóa Hết"),
                      onPressed: () {
                        if (notifications.isEmpty) return;
                        setState(() {
                          _selectedNotificationIndices.clear();
                          _selectedNotificationIndices.addAll(
                            List.generate(notifications.length, (i) => i),
                          );
                          _isSelectionMode = true;
                        });
                        _deleteSelectedNotifications();
                      },
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: RefreshIndicator(
                onRefresh: nav.fetchNotifications,
                child: ListView.builder(
                  itemCount: notifications.length,
                  itemBuilder: (ctx, index) {
                    final item = notifications[index];
                    final readBy = item['readBy'] as List?;
                    final isRead =
                        myName != null &&
                        readBy != null &&
                        readBy.contains(myName);
                    final type = item['type'] ?? 'INFO';
                    final isWarning = type == 'WARNING';
                    final isResolved = type == 'RESOLVED';
                    final isSelectMode = _isSelectionMode;
                    final isSelected = _selectedNotificationIndices.contains(
                      index,
                    );

                    final Map<String, dynamic> metadata =
                        (item['metadata'] is Map)
                        ? Map<String, dynamic>.from(item['metadata'])
                        : (item['metadata'] is String
                              ? jsonDecode(item['metadata'])
                              : {});

                    return GestureDetector(
                      onLongPress: () {
                        if (!_isSelectionMode) {
                          setState(() {
                            _isSelectionMode = true;
                            _selectedNotificationIndices.add(index);
                          });
                        }
                      },
                      onTap: () {
                        if (_isSelectionMode) {
                          setState(() {
                            if (isSelected) {
                              _selectedNotificationIndices.remove(index);
                            } else {
                              _selectedNotificationIndices.add(index);
                            }
                            if (_selectedNotificationIndices.isEmpty)
                              _isSelectionMode = false;
                          });
                        } else if (!isRead && item['id'] != null) {
                          _markNotificationRead(item['id'].toString());
                        }
                      },
                      child: Card(
                        color: isSelected
                            ? Colors.blue[100]
                            : (isResolved
                                  ? Colors.green[50]
                                  : (isRead
                                        ? Colors.white
                                        : Colors.orange[50])),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: isSelectMode
                              ? Checkbox(
                                  value: isSelected,
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selectedNotificationIndices.add(index);
                                      } else {
                                        _selectedNotificationIndices.remove(
                                          index,
                                        );
                                      }
                                      if (_selectedNotificationIndices.isEmpty)
                                        _isSelectionMode = false;
                                    });
                                  },
                                )
                              : Icon(
                                  isResolved
                                      ? Icons.check_circle
                                      : (isWarning
                                            ? Icons.warning
                                            : Icons.info),
                                  color: isResolved
                                      ? Colors.green
                                      : (isWarning
                                            ? Colors.orange
                                            : Colors.blue),
                                ),
                          title: Text(
                            item['message']?.toString() ?? '',
                            style: TextStyle(
                              fontWeight: isRead
                                  ? FontWeight.normal
                                  : FontWeight.bold,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item['time']?.toString() ?? ''),
                              if (isWarning && !isResolved)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.search, size: 16),
                                    label: const Text("KIỂM TRA NGAY"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () {
                                      if (metadata['action'] == 'RE_AUDIT') {
                                        _handleReAuditRequest(
                                          metadata['sku'].toString(),
                                          metadata['warehouse']?.toString(),
                                          item['id'].toString(),
                                        );
                                      } else if (metadata['targetCode'] !=
                                          null) {
                                        _handleCheckDiscrepancy(
                                          metadata['targetCode'].toString(),
                                          item['id'].toString(),
                                        );
                                      }
                                    },
                                  ),
                                ),
                            ],
                          ),
                          trailing: isResolved
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.check_circle_outline,
                                      color: Colors.green,
                                      size: 24,
                                    ),
                                    if (metadata['resolutionResult'] != null)
                                      Text(
                                        metadata['resolutionResult'].toString(),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                  ],
                                )
                              : null,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class SimpleScannerPage extends StatefulWidget {
  const SimpleScannerPage({super.key});

  @override
  State<SimpleScannerPage> createState() => _SimpleScannerPageState();
}

class _SimpleScannerPageState extends State<SimpleScannerPage> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isScanned = false;

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Quét mã QR/Barcode")),
      body: MobileScanner(
        onDetect: (capture) async {
          if (_isScanned) return;
          final barcode = capture.barcodes.firstOrNull;
          if (barcode != null && barcode.rawValue != null) {
            setState(() => _isScanned = true);
            try {
              await _audioPlayer.play(AssetSource('sounds/scan_beep.mp3'));
            } catch (e) {
              debugPrint('Audio play error: $e');
            }
            await Future.delayed(const Duration(milliseconds: 300));
            if (mounted) Navigator.pop(context, barcode.rawValue);
          }
        },
        errorBuilder: (context, error) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Lỗi Camera: Yêu cầu HTTPS hoặc quyền truy cập.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _showManualInputDialog(),
                child: const Text('Nhập mã thủ công'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showManualInputDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Nhập mã sản phẩm'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Camera QR scanner không khả dụng trên web.\nVui lòng nhập mã thủ công:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Mã sản phẩm (SKU)',
                border: OutlineInputBorder(),
                hintText: 'Ví dụ: SKU-001',
              ),
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context, value); // Return to previous screen
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Return to previous screen
            },
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context, value); // Return to previous screen
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

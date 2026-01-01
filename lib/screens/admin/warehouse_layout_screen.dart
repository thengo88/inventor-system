import 'dart:convert';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:inventor/models/product.dart';
import 'package:inventor/providers/product_provider.dart';
import 'package:inventor/providers/settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inventor/providers/auth_provider.dart';
import 'package:inventor/providers/notification_provider.dart';
import 'package:inventor/services/api_service.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'edit_product_screen.dart';

// --- Models for Customizable Layout ---

class BinConfig {
  String key;
  String? label; // Custom text for empty slots

  BinConfig({required this.key, this.label});

  Map<String, dynamic> toJson() => {'key': key, 'label': label};

  factory BinConfig.fromJson(Map<String, dynamic> json) =>
      BinConfig(key: json['key'], label: json['label']);
}

class TierConfig {
  String name;
  List<BinConfig> bins;
  String colorHex; // For tier theme

  TierConfig({
    required this.name,
    required this.bins,
    this.colorHex = 'FF2196F3',
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'bins': bins.map((e) => e.toJson()).toList(),
    'colorHex': colorHex,
  };

  factory TierConfig.fromJson(Map<String, dynamic> json) => TierConfig(
    name: json['name'],
    bins: (json['bins'] as List).map((e) => BinConfig.fromJson(e)).toList(),
    colorHex: json['colorHex'] ?? 'FF2196F3',
  );
}

class SectorConfig {
  String name;
  List<TierConfig> tiers;

  SectorConfig({required this.name, required this.tiers});

  Map<String, dynamic> toJson() => {
    'name': name,
    'tiers': tiers.map((e) => e.toJson()).toList(),
  };

  factory SectorConfig.fromJson(Map<String, dynamic> json) => SectorConfig(
    name: json['name'],
    tiers: (json['tiers'] as List).map((e) => TierConfig.fromJson(e)).toList(),
  );
}

// --- Main Screen ---

class WarehouseLayoutScreen extends StatefulWidget {
  final List<Product> allProducts;
  const WarehouseLayoutScreen({super.key, required this.allProducts});

  @override
  State<WarehouseLayoutScreen> createState() => _WarehouseLayoutScreenState();
}

class _WarehouseLayoutScreenState extends State<WarehouseLayoutScreen> {
  // Master Aisle List
  List<String> _aisleList = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'K'];
  String _selectedAisle = 'A';

  // Aisle ID -> List of Sectors
  Map<String, List<SectorConfig>> _layoutData = {};

  bool _isLoading = true;
  bool _isEditMode = false;

  Timer? _refreshTimer;
  bool _isInit = true;

  @override
  void initState() {
    super.initState();
    _loadAllConfig();
    // Auto-refresh every 2 seconds to ensure real-time data
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        context.read<ProductProvider>().fetchProducts();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInit) {
      final notifProvider = Provider.of<NotificationProvider>(context);
      notifProvider.addListener(() {
        if (mounted) {
          context.read<ProductProvider>().fetchProducts();
          // Also reload config if category is config
          // But since we can't easily check category here without deeper refactor,
          // simply reloading config is safe usually, or we assume specific event.
          // For now, let's rely on the fact that any system change might imply config change
          // or we can just fetch it periodically or add specific listening logic.
          // Let's reload config too to be safe for "instant update" request.
          _loadAllConfig(force: true);
        }
      });
      _isInit = false;
    }
  }

  Future<void> _loadAllConfig({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();

    // Force load products
    if (mounted) {
      await context.read<ProductProvider>().fetchProducts();
    }

    try {
      // 1. Try to load from Server first
      final serverConfig = await ApiService().getWarehouseConfig();

      if (serverConfig != null) {
        // Parse Server Config
        if (serverConfig['aisleList'] != null) {
          _aisleList = List<String>.from(serverConfig['aisleList']);
        }
        if (serverConfig['layoutData'] != null) {
          Map<String, dynamic> layoutJson = serverConfig['layoutData'];
          _layoutData = layoutJson.map(
            (key, value) => MapEntry(
              key,
              (value as List).map((e) => SectorConfig.fromJson(e)).toList(),
            ),
          );
        }

        // Cache it locally
        await prefs.setStringList('wh_aisle_list', _aisleList);
        await prefs.setString(
          'wh_layout_data_v2',
          jsonEncode(
            _layoutData.map(
              (key, value) =>
                  MapEntry(key, value.map((e) => e.toJson()).toList()),
            ),
          ),
        );
      } else if (!force) {
        // Fallback to local if server fails AND not forced reload
        _aisleList =
            prefs.getStringList('wh_aisle_list') ??
            ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'K'];

        String? layoutJson = prefs.getString('wh_layout_data_v2');
        if (layoutJson != null) {
          Map<String, dynamic> decoded = jsonDecode(layoutJson);
          _layoutData = decoded.map(
            (key, value) => MapEntry(
              key,
              (value as List).map((e) => SectorConfig.fromJson(e)).toList(),
            ),
          );
        } else {
          _generateDefaultLayout();
        }
      }
    } catch (e) {
      debugPrint("Config load error: $e");
      if (!force) _generateDefaultLayout();
    }

    // Ensure selected aisle is valid
    if (!_aisleList.contains(_selectedAisle) && _aisleList.isNotEmpty) {
      _selectedAisle = _aisleList[0];
    }

    // Load default if empty
    if (_layoutData.isEmpty) {
      _generateDefaultLayout();
    }

    // 3. Load Stocks
    await context.read<ProductProvider>().fetchErpStock();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _generateDefaultLayout() {
    _layoutData = {};
    for (String aisle in _aisleList) {
      List<SectorConfig> sectors = [];
      for (int i = 1; i <= 4; i++) {
        String subName = '$aisle$i';
        sectors.add(
          SectorConfig(
            name: 'Khu $subName',
            tiers: [
              TierConfig(
                name: 'TẦNG TRÊN (1-8)',
                colorHex: 'FF1976D2',
                bins: List.generate(
                  8,
                  (idx) => BinConfig(key: '$subName-${idx + 1}'),
                ),
              ),
              TierConfig(
                name: 'TẦNG DƯỚI (9-16)',
                colorHex: 'FFF57C00',
                bins: List.generate(
                  8,
                  (idx) => BinConfig(key: '$subName-${idx + 9}'),
                ),
              ),
            ],
          ),
        );
      }
      _layoutData[aisle] = sectors;
    }
  }

  Future<void> _saveConfig() async {
    // Save to Server
    final configData = {
      'aisleList': _aisleList,
      'layoutData': _layoutData.map(
        (key, value) => MapEntry(key, value.map((e) => e.toJson()).toList()),
      ),
    };

    final success = await ApiService().saveWarehouseConfig(configData);
    if (!success) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Lội lưu cấu hình lên Server")),
        );
    } else {
      // Also cache locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('wh_aisle_list', _aisleList);
      await prefs.setString(
        'wh_layout_data_v2',
        jsonEncode(configData['layoutData']),
      );
    }
  }

  // --- Management Actions ---

  void _addAisle() {
    // Check Admin
    if (!context.read<AuthProvider>().isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Chỉ Admin mới có quyền này"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    TextEditingController ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm Dãy mới'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Tên Dãy (ví dụ: L)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              String val = ctrl.text.trim().toUpperCase();
              if (val.isNotEmpty && !_aisleList.contains(val)) {
                setState(() {
                  _aisleList.add(val);
                  _layoutData[val] = []; // Empty aisle initially
                });
                _saveConfig();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  void _deleteAisle(String aisle) {
    if (!context.read<AuthProvider>().isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Chỉ Admin mới có quyền này"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Xóa Dãy $aisle?'),
        content: const Text('Toàn bộ cấu trúc bên trong dãy này sẽ bị mất.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                _aisleList.remove(aisle);
                _layoutData.remove(aisle);
                if (_selectedAisle == aisle && _aisleList.isNotEmpty) {
                  _selectedAisle = _aisleList[0];
                }
              });
              _saveConfig();
              Navigator.pop(ctx);
            },
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _editAisleName(String oldName, int index) {
    TextEditingController ctrl = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi tên dãy'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tên dãy mới',
            hintText: 'Ví dụ: A, B, C hoặc Khu 1, Khu 2...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = ctrl.text.trim();
              if (newName.isNotEmpty && newName != oldName) {
                setState(() {
                  // Update aisle list
                  _aisleList[index] = newName;

                  // Update layout data with new key
                  if (_layoutData.containsKey(oldName)) {
                    final data = _layoutData[oldName]!;
                    _layoutData.remove(oldName);
                    _layoutData[newName] = data;
                  }

                  // Update selected aisle if needed
                  if (_selectedAisle == oldName) {
                    _selectedAisle = newName;
                  }
                });
                _saveConfig();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _addSector() {
    setState(() {
      _layoutData[_selectedAisle]!.add(
        SectorConfig(name: 'Khu mới', tiers: []),
      );
    });
    _saveConfig();
  }

  void _editSector(SectorConfig sector) {
    TextEditingController ctrl = TextEditingController(text: sector.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chỉnh sửa Khu'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Tên Khu'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _layoutData[_selectedAisle]!.remove(sector));
              _saveConfig();
              Navigator.pop(ctx);
            },
            child: const Text('XÓA KHU', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => sector.name = ctrl.text);
              _saveConfig();
              Navigator.pop(ctx);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _addTier(SectorConfig sector) {
    setState(() {
      sector.tiers.add(
        TierConfig(name: 'Tầng mới', bins: [], colorHex: 'FF9E9E9E'),
      );
    });
    _saveConfig();
  }

  void _editTier(TierConfig tier, SectorConfig sector) {
    TextEditingController ctrl = TextEditingController(text: tier.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chỉnh sửa Tầng'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Tên Tầng'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => sector.tiers.remove(tier));
              _saveConfig();
              Navigator.pop(ctx);
            },
            child: const Text('XÓA TẦNG', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => tier.name = ctrl.text);
              _saveConfig();
              Navigator.pop(ctx);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _addBin(TierConfig tier) {
    setState(() {
      tier.bins.add(BinConfig(key: 'Mới'));
    });
    _saveConfig();
  }

  void _editBin(BinConfig bin, TierConfig tier) {
    TextEditingController keyCtrl = TextEditingController(text: bin.key);
    TextEditingController labelCtrl = TextEditingController(text: bin.label);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chỉnh sửa Vị trí'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyCtrl,
              decoration: const InputDecoration(
                labelText: 'Mã Vị Trí (vd: A1-1)',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(
                labelText: 'Ghi chú (hiển thị khi trống)',
                hintText: 'VD: Sọt lấy hàng, Pallet...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => tier.bins.remove(bin));
              _saveConfig();
              Navigator.pop(ctx);
            },
            child: const Text(
              'XÓA VỊ TRÍ',
              style: TextStyle(color: Colors.red),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                bin.key = keyCtrl.text;
                bin.label = labelCtrl.text.trim().isEmpty
                    ? null
                    : labelCtrl.text.trim();
              });
              _saveConfig();
              Navigator.pop(ctx);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  // --- UI Building ---

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5), // Professional background
      appBar: AppBar(
        title: const Text(
          'Sơ đồ Kho - Inventor Pro',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 2,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A237E),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle, color: Colors.blue),
            tooltip: 'Thêm sản phẩm',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditProductScreen()),
              );
            },
          ),
          if (context.read<AuthProvider>().isAdmin)
            IconButton(
              icon: Icon(
                _isEditMode ? Icons.check_circle : Icons.design_services,
                color: _isEditMode ? Colors.green : Colors.blue,
              ),
              tooltip: _isEditMode ? 'Hoàn tất sửa' : 'Sửa bố cục',
              onPressed: () {
                setState(() => _isEditMode = !_isEditMode);
                if (!_isEditMode) _saveConfig();
              },
            ),
          if (context.read<AuthProvider>().isAdmin)
            if (_isEditMode)
              IconButton(icon: const Icon(Icons.add_box), onPressed: _addAisle),
        ],
      ),
      body: Column(
        children: [
          _buildAisleTabs(),
          _buildLegend(),
          Expanded(child: _buildMainLayout()),
        ],
      ),
    );
  }

  Widget _buildAisleTabs() {
    return Container(
      height: 65,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(color: Colors.white),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _aisleList.length,
        itemBuilder: (ctx, i) {
          final aisle = _aisleList[i];
          final isSel = _selectedAisle == aisle;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onDoubleTap: () => _editAisleName(aisle, i),
              onLongPress: _isEditMode ? () => _deleteAisle(aisle) : null,
              child: InkWell(
                onTap: () => setState(() => _selectedAisle = aisle),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: isSel
                        ? const LinearGradient(
                            colors: [Color(0xFF1A237E), Color(0xFF3F51B5)],
                          )
                        : null,
                    color: isSel ? null : Colors.grey[100],
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: isSel ? Colors.transparent : Colors.grey[300]!,
                      width: 2,
                    ),
                    boxShadow: isSel
                        ? [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : [],
                  ),
                  child: Center(
                    child: Text(
                      'Dãy $aisle',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: isSel ? Colors.white : Colors.blueGrey[700],
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _legendNode(const Color(0xFF00FF00), 'CÓ HÀNG'),
          const SizedBox(width: 30),
          _legendNode(Colors.grey[300]!, 'VỊ TRÍ TRỐNG'),
          if (_isEditMode) ...[
            const SizedBox(width: 30),
            _legendNode(
              Colors.orange,
              'CHẾ ĐỘ THIẾT KẾ (ON)',
              isIcon: true,
              icon: Icons.edit,
            ),
          ],
        ],
      ),
    );
  }

  Widget _legendNode(
    Color color,
    String label, {
    bool isIcon = false,
    IconData? icon,
  }) {
    return Row(
      children: [
        isIcon
            ? Icon(icon, size: 16, color: color)
            : Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: Colors.blueGrey,
          ),
        ),
      ],
    );
  }

  Widget _buildMainLayout() {
    final sectors = _layoutData[_selectedAisle] ?? [];
    final bool isAndroid = !kIsWeb && Platform.isAndroid;

    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...sectors.map((s) => _buildSectorColumn(s)),
          if (_isEditMode)
            _buildAddButton('THÊM KHU', _addSector, height: 100, width: 280),
        ],
      ),
    );

    if (isAndroid) {
      return InteractiveViewer(
        boundaryMargin: const EdgeInsets.all(50),
        minScale: 0.01,
        maxScale: 3.0,
        scaleEnabled: true,
        constrained: false,
        child: content,
      );
    } else {
      // Desktop/Web: Use standard scrollbars and mouse wheel support
      return Scrollbar(
        thumbVisibility: true,
        thickness: 8,
        radius: const Radius.circular(4),
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: Scrollbar(
            thumbVisibility: true,
            thickness: 8,
            radius: const Radius.circular(4),
            notificationPredicate: (notif) => notif.depth == 1,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: content,
            ),
          ),
        ),
      );
    }
  }

  Widget _buildSectorColumn(SectorConfig sector) {
    return Container(
      width: 280, // Consistent pro width
      margin: const EdgeInsets.only(right: 20),
      child: Column(
        children: [
          // Corporate Header
          GestureDetector(
            onTap: _isEditMode ? () => _editSector(sector) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(
                  color: Colors.black.withOpacity(0.2),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      sector.name.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  if (_isEditMode)
                    const Icon(Icons.settings, color: Colors.white70, size: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),

          // Tiers
          ...sector.tiers.map((t) => _buildTierGroup(t, sector)),

          if (_isEditMode) _buildAddButton('THÊM TẦNG', () => _addTier(sector)),
        ],
      ),
    );
  }

  Widget _buildTierGroup(TierConfig tier, SectorConfig sector) {
    final tColor = Color(int.parse(tier.colorHex, radix: 16));
    return Column(
      children: [
        GestureDetector(
          onTap: _isEditMode ? () => _editTier(tier, sector) : null,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10, top: 5),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: tColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tColor.withOpacity(0.6), width: 2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  tier.name,
                  style: TextStyle(
                    color: tColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                if (_isEditMode)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.edit, size: 14, color: tColor),
                  ),
              ],
            ),
          ),
        ),

        // Bins
        ...tier.bins.map((b) => _buildBinItem(b, tier)),

        if (_isEditMode)
          _buildAddButton('CHÈN VỊ TRÍ', () => _addBin(tier), width: 150),

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildBinItem(BinConfig bin, TierConfig tier) {
    return Consumer<ProductProvider>(
      builder: (context, productProvider, child) {
        final themeColor = Color(int.parse(tier.colorHex, radix: 16));
        final allProducts = productProvider.products;
        final products = allProducts
            .where(
              (p) => p.layoutPosition.toUpperCase() == bin.key.toUpperCase(),
            )
            .toList();
        final hasProducts = products.isNotEmpty;
        final isLabeled = bin.label != null && bin.label!.isNotEmpty;
        final isActive = hasProducts || isLabeled;

        return GestureDetector(
          onTap: _isEditMode
              ? () => _editBin(bin, tier)
              : (hasProducts ? () => _showProducts(bin.key, products) : null),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: hasProducts
                  ? const Color(0xFF00FF00)
                  : (isLabeled
                        ? const Color(
                            0xFF006600,
                          ) // Dark Green for labeled slots
                        : Colors.white),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasProducts
                    ? themeColor
                    : (isLabeled
                          ? const Color(0xFF006600) // Match background
                          : Colors.grey[300]!),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: (hasProducts ? themeColor : Colors.grey).withOpacity(
                    0.15,
                  ),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  // Circular ID
                  Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: isActive
                            ? [themeColor.withOpacity(0.8), themeColor]
                            : [Colors.grey[200]!, Colors.grey[400]!],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: themeColor.withOpacity(0.4),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : [],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      bin.key,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: isActive ? Colors.white : Colors.black87,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const VerticalDivider(
                    width: 20,
                    thickness: 2,
                    color: Color(0xFFEEEEEE),
                  ),

                  // Products
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment:
                          CrossAxisAlignment.center, // Center contents
                      children: hasProducts
                          ? products.map((p) {
                              // Use the provider instance from Consumer
                              final double qty = productProvider
                                  .getCurrentStock(p, 'anc-wms');
                              final String qtyStr = NumberFormat(
                                '#,###',
                                'vi_VN',
                              ).format(qty);
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        p.sku,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.black,
                                          letterSpacing: 0.1,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: themeColor,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Text(
                                        qtyStr,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList()
                          : [
                              Text(
                                bin.label?.toUpperCase() ?? 'TRỐNG',
                                style: TextStyle(
                                  fontSize: isLabeled
                                      ? 18
                                      : 11, // Much bigger if labeled
                                  fontWeight: FontWeight.w900,
                                  color: isLabeled
                                      ? Colors.white
                                      : Colors.grey[400],
                                  letterSpacing: isLabeled ? 0.5 : 2,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddButton(
    String label,
    VoidCallback onTap, {
    double? height,
    double? width,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: width ?? double.infinity,
        height: height ?? 45,
        margin: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.blue.withOpacity(0.5),
            width: 2,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(10),
          color: Colors.blue.withOpacity(0.05),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_circle_outline, color: Colors.blue, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showProducts(String loc, List<Product> products) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.red, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'Vị trí $loc',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${products.length} mã hàng',
                      style: TextStyle(
                        color: Colors.blue[800],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1),
            Expanded(
              child: ListView.separated(
                itemCount: products.length,
                padding: const EdgeInsets.all(16),
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (ctx, i) => Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.blue[100],
                        child: const Icon(
                          Icons.inventory_2,
                          color: Color(0xFF1976D2),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              products[i].sku,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: Colors.blue,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              products[i].name,
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // Middle: Stock & Standard
                      Expanded(
                        flex: 5,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              'TCĐG: ${products[i].packagingStandard}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.blueGrey[400],
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Tồn kho: ${NumberFormat('#,###', 'vi_VN').format(context.read<ProductProvider>().getCurrentStock(products[i], 'anc-wms'))}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.blue[900],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Right: Actions
                      if (context.read<AuthProvider>().isAdmin)
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            InkWell(
                              onTap: () {
                                Navigator.pop(context);
                                _editProduct(products[i]);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: Icon(
                                  Icons.edit,
                                  size: 18,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () {
                                _confirmDeleteProduct(products[i]);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: Icon(
                                  Icons.delete,
                                  size: 18,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: const Text(
                    'ĐÓNG',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteProduct(Product product) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Xóa sản phẩm ${product.sku}?'),
        content: const Text('Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              if (product.id == null) return;
              final success = await context
                  .read<ProductProvider>()
                  .deleteProduct(product.id!);
              if (success && mounted) {
                Navigator.pop(context); // Close bottom sheet
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã xóa sản phẩm thành công')),
                );
                setState(() {});
              }
            },
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _editProduct(Product product) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditProductScreen(product: product)),
    );
    setState(() {}); // Refresh layout after editing
  }
}

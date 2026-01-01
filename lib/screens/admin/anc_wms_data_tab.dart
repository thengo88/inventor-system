import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../providers/product_provider.dart';

class AncWmsDataTab extends StatefulWidget {
  const AncWmsDataTab({super.key});

  @override
  State<AncWmsDataTab> createState() => _AncWmsDataTabState();
}

class _AncWmsDataTabState extends State<AncWmsDataTab> {
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  List<dynamic> _mergedData = [];
  String _searchQuery = "";
  String _selectedWarehouse = "Tất cả";
  List<String> _warehouses = ["Tất cả"];

  final ScrollController _horizontalController = ScrollController();
  final ScrollController _headerHorizontalController = ScrollController();
  final ScrollController _scrollableVerticalController = ScrollController();
  final ScrollController _fixedVerticalController = ScrollController();

  bool _isSyncingScroll = false;

  // Dynamic Columns Configuration (Advanced)
  late List<ErpColumn> _columns;
  List<String> _ignoredCols = [];

  // Hover state for highlighting
  int? _hoveredRowIndex;
  String? _hoveredColumnKey;

  @override
  void initState() {
    super.initState();
    _initColumns();
    _loadWarehouses();
    _loadColumnConfig().then((_) => _loadData());

    _horizontalController.addListener(() {
      if (_headerHorizontalController.hasClients) {
        _headerHorizontalController.jumpTo(_horizontalController.offset);
      }
    });

    _fixedVerticalController.addListener(() {
      if (!_isSyncingScroll && _scrollableVerticalController.hasClients) {
        _isSyncingScroll = true;
        _scrollableVerticalController.jumpTo(_fixedVerticalController.offset);
        _isSyncingScroll = false;
      }
    });

    _scrollableVerticalController.addListener(() {
      if (!_isSyncingScroll && _fixedVerticalController.hasClients) {
        _isSyncingScroll = true;
        _fixedVerticalController.jumpTo(_scrollableVerticalController.offset);
        _isSyncingScroll = false;
      }
    });

    _apiService.socket?.on('erp_update', (data) {
      if (mounted) _loadData();
    });

    _apiService.socket?.on('erp_update_all', (_) {
      if (mounted) _loadData();
    });
  }

  void _initColumns() {
    _columns = [
      ErpColumn(key: 'stt', label: 'STT', width: 50, isFixed: true),
      ErpColumn(key: 'sku', label: 'Code', width: 140, isFixed: true),
      ErpColumn(key: 'sku_plain', label: 'Mã liền', width: 130, isFixed: true),

      ErpColumn(
        key: 'name',
        label: 'Tên vật tư',
        width: 250,
        isFixed: true,
        align: TextAlign.left,
      ),
      ErpColumn(key: 'warehouse', label: 'Kho', width: 80),
      ErpColumn(key: 'quantity', label: 'Qty(WMS)', width: 100),
      ErpColumn(key: 'kk1', label: 'KK1', width: 70),
      ErpColumn(key: 'kk2', label: 'KK2', width: 70),
      ErpColumn(key: 'kk3', label: 'KK3', width: 70),
      ErpColumn(key: 'kk4', label: 'KK4', width: 70),
      ErpColumn(key: 'kk5', label: 'KK5', width: 70),
      ErpColumn(key: 'kk6', label: 'KK6', width: 70),
      ErpColumn(key: 'kk7', label: 'KK7', width: 70),
      ErpColumn(key: 'kk8', label: 'KK8', width: 70),
      ErpColumn(key: 'kk9', label: 'KK9', width: 70),
      ErpColumn(key: 'kk10', label: 'KK10', width: 70),
      ErpColumn(
        key: 'total_kk',
        label: 'Tổng KK',
        width: 100,
        weight: FontWeight.bold,
        addKeys: [
          'kk1',
          'kk2',
          'kk3',
          'kk4',
          'kk5',
          'kk6',
          'kk7',
          'kk8',
          'kk9',
          'kk10',
        ],
      ),
      ErpColumn(
        key: 'diff',
        label: 'Chênh lệch',
        width: 110,
        weight: FontWeight.bold,
        addKeys: ['total_kk'],
        subKeys: ['quantity'],
      ),
      ErpColumn(key: 'merge_diff', label: 'CL NN', width: 110, isSpecial: true),
      ErpColumn(
        key: 'packing_diff',
        label: 'Packing/Bù',
        width: 180,
        align: TextAlign.left,
      ),
      ErpColumn(key: 're_audit', label: 'Kiểm lại', width: 80, isSpecial: true),
    ];
  }

  Future<void> _loadColumnConfig() async {
    final prefs = await SharedPreferences.getInstance();
    _ignoredCols = prefs.getStringList('ignored_wms_cols') ?? [];
    final String? jsonStr = prefs.getString('wms_column_config');
    if (jsonStr != null) {
      try {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        final List<ErpColumn> loaded = decoded
            .map((e) => ErpColumn.fromJson(e))
            .toList();
        if (!loaded.any((c) => c.key == 'stt')) {
          loaded.insert(
            0,
            ErpColumn(key: 'stt', label: 'STT', width: 50, isFixed: true),
          );
        }

        if (!loaded.any((c) => c.key == 'sku_plain')) {
          int skuIdx = loaded.indexWhere((c) => c.key == 'sku');
          if (skuIdx != -1) {
            loaded.insert(
              skuIdx + 1,
              ErpColumn(
                key: 'sku_plain',
                label: 'Mã liền',
                width: 130,
                isFixed: true,
              ),
            );
          }
        }

        setState(() => _columns = loaded);
      } catch (e) {
        debugPrint('Error loading WMS column config: $e');
      }
    }
  }

  Future<void> _saveColumnConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'wms_column_config',
      jsonEncode(_columns.map((e) => e.toJson()).toList()),
    );
    await prefs.setStringList('ignored_wms_cols', _ignoredCols);
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _headerHorizontalController.dispose();
    _fixedVerticalController.dispose();
    _scrollableVerticalController.dispose();
    super.dispose();
  }

  Future<void> _loadWarehouses() async {
    try {
      final list = await _apiService.getErpWarehouses();
      if (mounted) setState(() => _warehouses = ["Tất cả", ...list]);
    } catch (e) {
      debugPrint('Load warehouses error: $e');
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final erpStockList = await _apiService.getErpStockFromDb(
        warehouse: _selectedWarehouse == "Tất cả" ? "" : _selectedWarehouse,
      );
      final productProvider = context.read<ProductProvider>();
      await productProvider.fetchProducts();
      final products = productProvider.products;

      final Map<String, dynamic> wmsSkusMap = {
        for (var p in products) p.sku: p,
      };
      final List<dynamic> result = [];
      final Set<String> processedSkus = {};
      final Set<String> dynamicKeys = {};

      for (var item in erpStockList) {
        final sku = item['sku']?.toString() ?? '';
        if (wmsSkusMap.containsKey(sku)) {
          final p = wmsSkusMap[sku];
          item['quantity'] = p.stock.toString();
          item['name'] = p.name;
          item['warehouse'] = p.layoutPosition;

          _processCustomData(item, dynamicKeys);
          _processMergedSkus(item);

          result.add(item);
          processedSkus.add(sku);
        }
      }

      for (var p in products) {
        if (!processedSkus.contains(p.sku) &&
            (_selectedWarehouse == "Tất cả" ||
                p.layoutPosition == _selectedWarehouse)) {
          final Map<String, dynamic> virtualItem = {
            'sku': p.sku,
            'sku_plain': p.skuPlain,
            'name': p.name,
            'warehouse': p.layoutPosition,
            'quantity': p.stock.toString(),
            'kk1': '0',
            'kk2': '0',
            'kk3': '0',
            'kk4': '0',
            'kk5': '0',
            'kk6': '0',
            'kk7': '0',
            'kk8': '0',
            'kk9': '0',
            'kk10': '0',
            'total_kk': '0',
            'difference': (0 - p.stock).toString(),
            'merged_skus': [],
            'custom_data': '{}',
          };

          result.add(virtualItem);
        }
      }

      // Handle Dynamic Columns Injection
      if (mounted && result.isNotEmpty) {
        final currentKeys = _columns.map((c) => c.key).toSet();
        int insertIndex = 3; // After STT, Code, Name
        final sortedKeys = dynamicKeys.toList()..sort();
        for (var key in sortedKeys) {
          if (!currentKeys.contains(key)) {
            _columns.insert(
              insertIndex++,
              ErpColumn(
                key: key,
                label: key,
                width: 100,
                align: TextAlign.center,
              ),
            );
          }
        }
      }

      setState(() => _mergedData = result);
    } catch (e) {
      debugPrint('Load ANC-WMS data error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _processCustomData(dynamic item, Set<String> dynamicKeys) {
    if (item['custom_data'] != null) {
      try {
        final cd = item['custom_data'];
        Map<String, dynamic> customMap = {};
        if (cd is String && cd != 'null' && cd.isNotEmpty) {
          customMap = jsonDecode(cd);
        } else if (cd is Map) {
          customMap = Map<String, dynamic>.from(cd);
        }
        customMap.forEach((k, v) {
          item[k] = v;
          if (!_ignoredCols.contains(k)) dynamicKeys.add(k);
        });
      } catch (e) {}
    }
  }

  void _processMergedSkus(dynamic item) {
    if (item['merged_skus'] != null) {
      try {
        final ms = item['merged_skus'];
        if (ms is String && ms.startsWith('[')) {
          item['merged_skus'] = jsonDecode(ms);
        } else if (ms is! List) {
          item['merged_skus'] = [];
        }
      } catch (e) {
        item['merged_skus'] = [];
      }
    } else {
      item['merged_skus'] = [];
    }
  }

  Future<void> _uploadDynamicExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _isLoading = true);
      try {
        final res = await _apiService.uploadDynamicColumnsExcel(
          File(result.files.single.path!),
        );
        if (res != null) {
          _loadData();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cập nhật ${res['successCount']} cột động')),
          );
        }
      } catch (e) {
        debugPrint('Dynamic upload error: $e');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _isLoading = true);
    try {
      final excel = excel_pkg.Excel.createExcel();
      final sheetName = 'ANC-WMS Data';
      excel.rename('Sheet1', sheetName);
      final sheet = excel[sheetName];

      final visibleCols = _columns.where((c) => c.isVisible).toList();
      for (int i = 0; i < visibleCols.length; i++) {
        final cell = sheet.cell(
          excel_pkg.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
        );
        cell.value = excel_pkg.TextCellValue(visibleCols[i].label);
        cell.cellStyle = excel_pkg.CellStyle(
          bold: true,
          horizontalAlign: excel_pkg.HorizontalAlign.Center,
          backgroundColorHex: excel_pkg.ExcelColor.fromHexString('#CCCCCC'),
        );
      }

      final filtered = _getFilteredData();
      for (int r = 0; r < filtered.length; r++) {
        final item = filtered[r];
        for (int c = 0; c < visibleCols.length; c++) {
          final col = visibleCols[c];
          final cell = sheet.cell(
            excel_pkg.CellIndex.indexByColumnRow(
              columnIndex: c,
              rowIndex: r + 1,
            ),
          );

          dynamic val;
          if (col.key == 'stt')
            val = r + 1;
          else if (col.key == 'diff' || col.key == 'total_kk')
            val = _calculateFormulaValue(col, item);
          else {
            val = item[col.key];
            if (val == null || val == '0' || val == 0) val = '';
          }

          if (val is num) {
            cell.value = val is int
                ? excel_pkg.IntCellValue(val)
                : excel_pkg.DoubleCellValue(val.toDouble());
          } else {
            cell.value = excel_pkg.TextCellValue(val.toString());
          }
        }
      }

      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Lưu file Excel',
        fileName:
            'WMS_Export_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.xlsx',
        allowedExtensions: ['xlsx'],
      );

      if (outputFile != null) {
        if (!outputFile.endsWith('.xlsx')) outputFile += '.xlsx';
        final fileBytes = excel.save();
        if (fileBytes != null) {
          File(outputFile).writeAsBytesSync(fileBytes);
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Đã lưu file: $outputFile'),
                backgroundColor: Colors.green,
              ),
            );
        }
      }
    } catch (e) {
      debugPrint('Export error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<dynamic> _getFilteredData() {
    return _mergedData.where((item) {
      final q = _searchQuery.toLowerCase();
      final matchesSearch =
          (item['sku'] ?? '').toString().toLowerCase().contains(q) ||
          (item['sku_plain'] ?? '').toString().toLowerCase().contains(q) ||
          (item['name'] ?? '').toString().toLowerCase().contains(q);

      final matchesWarehouse =
          _selectedWarehouse == "Tất cả" ||
          (item['warehouse'] ?? '').toString() == _selectedWarehouse;
      return matchesSearch && matchesWarehouse;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _getFilteredData();
    final currencyFormat = NumberFormat("#,###.##", "en_US");

    double totalQty = 0;
    double totalKk = 0;
    for (var item in filtered) {
      totalQty += _parseSafe(item['quantity']);
      totalKk += _calculateFormulaValue(
        _columns.firstWhere((c) => c.key == 'total_kk'),
        item,
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.indigo[800]!, Colors.indigo[500]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.indigo.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildSummaryItemPremium(
                        "MÃ SỐ (WMS)",
                        "${filtered.length}",
                        Icons.inventory_2_outlined,
                      ),
                    ),
                    Container(height: 35, width: 1, color: Colors.white24),
                    Expanded(
                      child: _buildSummaryItemPremium(
                        "TỔNG QTY (H.THỐNG)",
                        currencyFormat.format(totalQty),
                        Icons.analytics_outlined,
                      ),
                    ),
                    Container(height: 35, width: 1, color: Colors.white24),
                    Expanded(
                      child: _buildSummaryItemPremium(
                        "TỔNG QTY (KK)",
                        currencyFormat.format(totalKk),
                        Icons.fact_check_outlined,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        hintText: 'Tìm SKU hoặc tên...',
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _warehouses.contains(_selectedWarehouse)
                        ? _selectedWarehouse
                        : "Tất cả",
                    items: _warehouses
                        .map(
                          (w) => DropdownMenuItem(
                            value: w,
                            child: Text(
                              w,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      _selectedWarehouse = v!;
                      _loadData();
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _actionBtn(
                    Icons.download,
                    "Xuất Excel",
                    _exportExcel,
                    color: Colors.teal,
                  ),
                  _actionBtn(
                    Icons.playlist_add,
                    "Cột động",
                    _uploadDynamicExcel,
                    color: Colors.teal[600],
                  ),
                  _actionBtn(
                    Icons.note_add,
                    "Packing",
                    _showPackingDialog,
                    color: Colors.orange,
                  ),
                  _actionBtn(
                    Icons.view_column_rounded,
                    "Tùy chỉnh cột",
                    _showColumnConfig,
                    color: Colors.blueGrey,
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading && _mergedData.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _buildTable(filtered),
        ),
      ],
    );
  }

  Widget _actionBtn(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? color,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildSummaryItemPremium(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 14),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: Colors.white70,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildTable(List<dynamic> data) {
    if (data.isEmpty) return const Center(child: Text("Không có dữ liệu"));

    final visibleCols = _columns.where((c) => c.isVisible).toList();
    final fixedCols = visibleCols.where((c) => c.isFixed).toList();
    final scrollCols = visibleCols.where((c) => !c.isFixed).toList();

    double fixedWidth = fixedCols.fold(0, (sum, c) => sum + c.width);
    double scrollWidth = scrollCols.fold(0, (sum, c) => sum + c.width);

    return Row(
      children: [
        if (fixedCols.isNotEmpty)
          SizedBox(width: fixedWidth, child: _buildTablePart(data, fixedCols)),
        Expanded(
          child: Column(
            children: [
              SingleChildScrollView(
                controller: _headerHorizontalController,
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Container(
                  color: Colors.blueGrey[50],
                  width: scrollWidth,
                  height: 34,
                  child: Row(
                    children: scrollCols
                        .map(
                          (c) => _cell(c.label, c.width, true, align: c.align),
                        )
                        .toList(),
                  ),
                ),
              ),
              Expanded(
                child: Scrollbar(
                  controller: _horizontalController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _horizontalController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: scrollWidth,
                      child: _buildTablePart(
                        data,
                        scrollCols,
                        isHeaderVisible: false,
                        isScrollable: true,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTablePart(
    List<dynamic> data,
    List<ErpColumn> cols, {
    bool isHeaderVisible = true,
    bool isScrollable = false,
  }) {
    return Column(
      children: [
        if (isHeaderVisible)
          Container(
            color: Colors.blueGrey[50],
            height: 34,
            child: Row(
              children: cols
                  .map((c) => _cell(c.label, c.width, true, align: c.align))
                  .toList(),
            ),
          ),
        const Divider(height: 1, thickness: 1),
        Expanded(
          child: ListView.builder(
            controller: isScrollable
                ? _scrollableVerticalController
                : _fixedVerticalController,
            itemCount: data.length,
            itemBuilder: (ctx, idx) {
              final item = data[idx];
              final cellBg = idx % 2 == 0
                  ? Colors.white
                  : Colors.grey[50]!.withOpacity(0.5);
              return SizedBox(
                height: 34,
                child: Row(
                  children: cols
                      .map((c) => _renderDataCell(c, item, idx, data, cellBg))
                      .toList(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMergeCell(
    dynamic item,
    double w, {
    Color? cellBg,
    bool isDisplayLeader = false,
    bool isAdjacentBack = false,
    bool isAdjacentNext = false,
    double verticalOffset = 0,
  }) {
    final val = _parseSafe(item['diff_nn']);
    final txtColor = val < 0 ? Colors.red : Colors.green;
    final text = val == 0 ? '' : (val > 0 ? '+$val' : '$val');

    return Container(
      width: w,
      height: double.infinity,
      clipBehavior: Clip.none, // Allow overflow for multi-row merging
      decoration: BoxDecoration(
        color: cellBg,
        border: Border(
          right: BorderSide(color: Colors.grey[200]!),
          bottom: isAdjacentNext
              ? BorderSide.none
              : BorderSide(color: Colors.grey[200]!),
        ),
      ),
      alignment: Alignment.center,
      child: isDisplayLeader
          ? Transform.translate(
              offset: Offset(0, verticalOffset),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                decoration: BoxDecoration(
                  color: val != 0
                      ? txtColor.withOpacity(0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item['merged_skus'] != null &&
                        (item['merged_skus'] as List).length > 1)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(Icons.link, size: 14, color: txtColor),
                      ),
                    Text(
                      text,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: txtColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _renderDataCell(
    ErpColumn col,
    dynamic item,
    int rowIndex,
    List<dynamic> allData,
    Color rowBg,
  ) {
    Color? cellBg = rowBg;
    if (_hoveredRowIndex == rowIndex || _hoveredColumnKey == col.key)
      cellBg = Color.alphaBlend(Colors.blue.withOpacity(0.05), rowBg);

    // Grouping logic
    String groupKey = "";
    if (item['merged_skus'] != null && item['merged_skus'] is List) {
      final ms = List<String>.from(
        (item['merged_skus'] as List).map((e) => e.toString().trim()),
      );
      if (ms.length > 1) {
        ms.sort();
        groupKey = ms.join('|');
      }
    }

    Widget content;
    if (col.key == 'stt') {
      content = _cell(
        (rowIndex + 1).toString(),
        col.width,
        false,
        cellBg: cellBg,
      );
    } else if (col.key == 'sku') {
      content = InkWell(
        onTap: () => _showMergeDiffDialog(item),
        child: _cell(
          item['sku'] ?? '',
          col.width,
          false,
          weight: FontWeight.bold,
          color: Colors.blue,
          cellBg: cellBg,
        ),
      );
    } else if (col.key == 'name' ||
        col.key == 'sku_plain' ||
        col.key == 'warehouse' ||
        col.key == 'packing_diff' || // Handle packing_diff as string
        (col.addKeys == null &&
            col.subKeys == null &&
            item[col.key] is String &&
            double.tryParse(item[col.key].toString()) == null)) {
      String textValue = item[col.key]?.toString() ?? '';
      content = _cell(
        textValue,
        col.width,
        false,
        align: col.align,
        weight: col.weight,
        cellBg: cellBg,
      );
    } else if (col.key == 'merge_diff') {
      bool isAdjacentBack = false;
      bool isAdjacentNext = false;
      bool isDisplayLeader = false;
      double verticalOffset = 0;

      if (groupKey.isNotEmpty) {
        // Find contiguous group bounds
        int contiguousStart = rowIndex;
        while (contiguousStart > 0) {
          final prevItem = allData[contiguousStart - 1];
          String pk = "";
          if (prevItem['merged_skus'] is List) {
            final ms = List<String>.from(
              (prevItem['merged_skus'] as List).map((e) => e.toString().trim()),
            );
            if (ms.length > 1) {
              ms.sort();
              pk = ms.join('|');
            }
          }
          if (pk == groupKey) {
            contiguousStart--;
          } else {
            break;
          }
        }

        int contiguousEnd = rowIndex;
        while (contiguousEnd < allData.length - 1) {
          final nextItem = allData[contiguousEnd + 1];
          String nk = "";
          if (nextItem['merged_skus'] is List) {
            final ms = List<String>.from(
              (nextItem['merged_skus'] as List).map((e) => e.toString().trim()),
            );
            if (ms.length > 1) {
              ms.sort();
              nk = ms.join('|');
            }
          }
          if (nk == groupKey) {
            contiguousEnd++;
          } else {
            break;
          }
        }

        isAdjacentBack = rowIndex > contiguousStart;
        isAdjacentNext = rowIndex < contiguousEnd;

        int count = contiguousEnd - contiguousStart + 1;

        // Logic: Render on the LAST row (contiguousEnd) to avoid Z-order issues
        if (rowIndex == contiguousEnd) {
          isDisplayLeader = true;
          verticalOffset = (1.0 - count) * 17.0;
        } else {
          isDisplayLeader = false;
        }
      } else {
        isDisplayLeader = true;
      }

      content = _buildMergeCell(
        item,
        col.width,
        cellBg: cellBg,
        isDisplayLeader: isDisplayLeader,
        isAdjacentBack: isAdjacentBack,
        isAdjacentNext: isAdjacentNext,
        verticalOffset: verticalOffset,
      );
    } else if (col.key == 're_audit') {
      content = Container(
        width: col.width,
        decoration: BoxDecoration(
          color: cellBg,
          border: Border(
            right: BorderSide(color: Colors.grey[200]!),
            bottom: BorderSide(color: Colors.grey[200]!),
          ),
        ),
        child: IconButton(
          icon: const Icon(
            Icons.notifications_active,
            size: 16,
            color: Colors.orange,
          ),
          onPressed: () => _requestReAudit(item),
        ),
      );
    } else {
      final numericValue = _calculateFormulaValue(col, item);
      final display = (numericValue % 1 == 0)
          ? numericValue.toInt().toString()
          : numericValue.toStringAsFixed(1);
      final txtColor = col.key == 'diff'
          ? (numericValue < 0
                ? Colors.red
                : (numericValue > 0 ? Colors.green : null))
          : null;
      content = _cell(
        display == '0' && col.key.startsWith('kk') ? '' : display,
        col.width,
        false,
        align: col.align,
        weight: col.weight,
        color: txtColor,
        cellBg: cellBg,
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() {
        _hoveredRowIndex = rowIndex;
        _hoveredColumnKey = col.key;
      }),
      onExit: (_) => setState(() {
        _hoveredRowIndex = null;
        _hoveredColumnKey = null;
      }),
      child: content,
    );
  }

  Widget _cell(
    String t,
    double w,
    bool h, {
    TextAlign align = TextAlign.center,
    Color? color,
    FontWeight? weight,
    Color? cellBg,
  }) {
    return Container(
      width: w,
      height: double.infinity,
      alignment: align == TextAlign.left
          ? Alignment.centerLeft
          : align == TextAlign.right
          ? Alignment.centerRight
          : Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: cellBg,
        border: Border(
          right: BorderSide(color: Colors.grey[200]!),
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Text(
        t,
        style: TextStyle(
          fontSize: 11,
          fontWeight: h ? FontWeight.bold : weight,
          color: h ? Colors.black87 : color,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  double _calculateFormulaValue(ErpColumn col, dynamic item) {
    if ((col.addKeys == null || col.addKeys!.isEmpty) &&
        (col.subKeys == null || col.subKeys!.isEmpty))
      return _parseSafe(item[col.key]);
    double res = 0;
    for (var k in col.addKeys ?? [])
      res += _calculateFormulaValue(
        _columns.firstWhere(
          (c) => c.key == k,
          orElse: () => ErpColumn(key: k, label: '', width: 0),
        ),
        item,
      );
    for (var k in col.subKeys ?? [])
      res -= _calculateFormulaValue(
        _columns.firstWhere(
          (c) => c.key == k,
          orElse: () => ErpColumn(key: k, label: '', width: 0),
        ),
        item,
      );
    return res;
  }

  double _parseSafe(dynamic v) =>
      double.tryParse(v?.toString().replaceAll(',', '') ?? '0') ?? 0;

  void _showMergeDiffDialog(Map<String, dynamic> currentItem) {
    final currentSku = currentItem['sku']?.toString().trim() ?? '';
    final relatedItems = _mergedData.where((i) {
      final s = i['sku']?.toString().trim() ?? '';
      return s.isNotEmpty;
    }).toList();

    // Find neighbors for context
    final idx = relatedItems.indexWhere(
      (i) => i['sku']?.toString().trim() == currentSku,
    );
    final contextList = relatedItems.sublist(
      (idx - 5).clamp(0, relatedItems.length),
      (idx + 6).clamp(0, relatedItems.length),
    );

    final selectedSkus = <String>{currentSku};
    if (currentItem['merged_skus'] is List)
      selectedSkus.addAll(List<String>.from(currentItem['merged_skus']));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final totalDiff = _mergedData
              .where((i) => selectedSkus.contains(i['sku']?.toString().trim()))
              .fold<double>(
                0,
                (sum, i) =>
                    sum +
                    _calculateFormulaValue(
                      _columns.firstWhere((c) => c.key == 'diff'),
                      i,
                    ),
              );
          return AlertDialog(
            title: Text('Ghép chênh lệch: $currentSku'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 300,
                    child: ListView.builder(
                      itemCount: contextList.length,
                      itemBuilder: (c, i) {
                        final item = contextList[i];
                        final sku = item['sku']?.toString().trim() ?? '';
                        return CheckboxListTile(
                          title: Text(
                            sku,
                            style: TextStyle(
                              fontWeight: sku == currentSku
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            'CL: ${_calculateFormulaValue(_columns.firstWhere((c) => c.key == 'diff'), item).toStringAsFixed(0)}',
                          ),
                          value: selectedSkus.contains(sku),
                          onChanged: (v) => setS(
                            () => v!
                                ? selectedSkus.add(sku)
                                : selectedSkus.remove(sku),
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(),
                  Text(
                    'Tổng CL: ${totalDiff.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: totalDiff < 0 ? Colors.red : Colors.green,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (await _apiService.updateErpDiffNn(
                    currentSku,
                    totalDiff.toString(),
                    mergedSkus: selectedSkus.toList(),
                  )) {
                    Navigator.pop(ctx);
                    _loadData();
                  }
                },
                child: const Text('Lưu'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _addColumnDialog() {
    String label = "";
    String key = "";
    double width = 100;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Thêm cột mới"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: "Tên cột (Hiển thị)",
              ),
              onChanged: (v) => label = v,
            ),
            TextField(
              decoration: const InputDecoration(
                labelText: "Mã cột (Key dữ liệu)",
              ),
              onChanged: (v) => key = v,
            ),
            TextField(
              decoration: const InputDecoration(labelText: "Chiều rộng (px)"),
              keyboardType: TextInputType.number,
              onChanged: (v) => width = double.tryParse(v) ?? 100,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Hủy"),
          ),
          ElevatedButton(
            onPressed: () {
              if (label.isNotEmpty && key.isNotEmpty) {
                setState(() {
                  _columns.add(ErpColumn(key: key, label: label, width: width));
                  _saveColumnConfig();
                });
                Navigator.pop(context);
                _showColumnConfig();
              }
            },
            child: const Text("Thêm"),
          ),
        ],
      ),
    );
  }

  void _editColumnDialog(int index) {
    final col = _columns[index];
    final labelCtrl = TextEditingController(text: col.label);
    final keyCtrl = TextEditingController(text: col.key);
    final widthCtrl = TextEditingController(text: col.width.toInt().toString());
    List<String> tempAddKeys = List.from(col.addKeys ?? []);
    List<String> tempSubKeys = List.from(col.subKeys ?? []);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setEditState) {
          return AlertDialog(
            title: Text("Chỉnh sửa cột: ${col.label}"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: labelCtrl,
                    decoration: const InputDecoration(
                      labelText: "Tên hiển thị",
                    ),
                  ),
                  TextField(
                    controller: keyCtrl,
                    decoration: const InputDecoration(labelText: "Mã (Key)"),
                  ),
                  TextField(
                    controller: widthCtrl,
                    decoration: const InputDecoration(
                      labelText: "Chiều rộng (px)",
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "CÔNG THỨC TÍNH TOÁN",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.blueGrey,
                    ),
                  ),
                  const Divider(),
                  _buildFormulaSelector(
                    "Cộng (+)",
                    tempAddKeys,
                    (keys) => setEditState(() => tempAddKeys = keys),
                  ),
                  const SizedBox(height: 8),
                  _buildFormulaSelector(
                    "Trừ (-)",
                    tempSubKeys,
                    (keys) => setEditState(() => tempSubKeys = keys),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Hủy"),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _columns[index] = ErpColumn(
                      key: keyCtrl.text,
                      label: labelCtrl.text,
                      width: double.tryParse(widthCtrl.text) ?? col.width,
                      isFixed: col.isFixed,
                      isVisible: col.isVisible,
                      align: col.align,
                      weight: col.weight,
                      isSpecial: col.isSpecial,
                      addKeys: tempAddKeys.isEmpty ? null : tempAddKeys,
                      subKeys: tempSubKeys.isEmpty ? null : tempSubKeys,
                    );
                    _saveColumnConfig();
                  });
                  Navigator.pop(context);
                  _showColumnConfig();
                },
                child: const Text("Lưu thay đổi"),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFormulaSelector(
    String title,
    List<String> selectedKeys,
    Function(List<String>) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        ),
        Wrap(
          spacing: 4,
          children: _columns.where((c) => !c.isSpecial).map((c) {
            final isSelected = selectedKeys.contains(c.key);
            return FilterChip(
              label: Text(c.label, style: const TextStyle(fontSize: 10)),
              selected: isSelected,
              onSelected: (val) {
                final newList = List<String>.from(selectedKeys);
                if (val)
                  newList.add(c.key);
                else
                  newList.remove(c.key);
                onChanged(newList);
              },
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showPackingDialog() {
    // ... Existing implementation
    final TextEditingController skuCtrl = TextEditingController();
    final TextEditingController noteCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Nhập Packing/Bù hàng"),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Autocomplete<String>(
                optionsBuilder: (v) => _mergedData
                    .where(
                      (i) => (i['sku'] ?? '').toString().toLowerCase().contains(
                        v.text.toLowerCase(),
                      ),
                    )
                    .map((i) => i['sku']?.toString() ?? ''),
                onSelected: (v) => skuCtrl.text = v,
                fieldViewBuilder: (c, ctrl, f, o) {
                  ctrl.text = skuCtrl.text;
                  return TextField(
                    controller: ctrl,
                    focusNode: f,
                    decoration: const InputDecoration(labelText: "Mã số (SKU)"),
                  );
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: "Nội dung ghi chú",
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Hủy"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (await _apiService.updateErpPackingNote(
                skuCtrl.text,
                noteCtrl.text,
              )) {
                Navigator.pop(ctx);
                _loadData();
              }
            },
            child: const Text("Lưu"),
          ),
        ],
      ),
    );
  }

  void _showColumnConfig() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Tùy chỉnh bảng dữ liệu"),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _addColumnDialog();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text("Thêm cột"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              height: 500,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      "(Kéo thả để sắp xếp vị trí, dùng Ghim để cố định)",
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ReorderableListView(
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (newIndex > oldIndex) newIndex -= 1;
                          final item = _columns.removeAt(oldIndex);
                          _columns.insert(newIndex, item);
                          _saveColumnConfig();
                        });
                        setDialogState(() {});
                      },
                      children: _columns.asMap().entries.map((entry) {
                        final col = entry.value;
                        return ListTile(
                          key: ValueKey(col.key),
                          leading: const Icon(Icons.drag_indicator),
                          title: Text(col.label),
                          subtitle: Text(
                            "Key: ${col.key} | Rộng: ${col.width.toInt()}px",
                            style: const TextStyle(fontSize: 10),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.edit_note,
                                  color: Colors.blueGrey,
                                ),
                                onPressed: () {
                                  Navigator.pop(context);
                                  _editColumnDialog(entry.key);
                                },
                                tooltip: "Sửa cột",
                              ),
                              IconButton(
                                icon: Icon(
                                  col.isFixed
                                      ? Icons.push_pin
                                      : Icons.push_pin_outlined,
                                  color: col.isFixed
                                      ? Colors.blue
                                      : Colors.grey,
                                ),
                                onPressed: () {
                                  setState(() {
                                    col.isFixed = !col.isFixed;
                                    _saveColumnConfig();
                                  });
                                  setDialogState(() {});
                                },
                                tooltip: "Cố định cột",
                              ),
                              Switch(
                                value: col.isVisible,
                                activeColor: Colors.blue,
                                onChanged: (val) {
                                  setState(() {
                                    col.isVisible = val;
                                    _saveColumnConfig();
                                  });
                                  setDialogState(() {});
                                },
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () {
                                  setState(() {
                                    final removed = _columns.removeAt(
                                      entry.key,
                                    );
                                    if (!_ignoredCols.contains(removed.key)) {
                                      _ignoredCols.add(removed.key);
                                    }
                                    _saveColumnConfig();
                                  });
                                  setDialogState(() {});
                                },
                                tooltip: "Xóa cột",
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Hoàn tất"),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _requestReAudit(Map<String, dynamic> item) async {
    final sku = item['sku'] ?? '';
    final success = await _apiService.sendNotification(
      message: 'Yêu cầu kiểm lại ANC-WMS: $sku',
      type: 'WARNING',
      metadata: {'sku': sku, 'action': 'RE_AUDIT'},
    );
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'Đã gửi yêu cầu $sku' : 'Thất bại')),
      );
  }
}

class ErpColumn {
  final String key;
  final String label;
  final double width;
  bool isFixed;
  bool isVisible;
  final TextAlign align;
  final FontWeight? weight;
  final bool isSpecial;
  final List<String>? addKeys;
  final List<String>? subKeys;

  ErpColumn({
    required this.key,
    required this.label,
    required this.width,
    this.isFixed = false,
    this.isVisible = true,
    this.align = TextAlign.center,
    this.weight,
    this.isSpecial = false,
    this.addKeys,
    this.subKeys,
  });

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'width': width,
    'isFixed': isFixed,
    'isVisible': isVisible,
    'align': align.index,
    'weight': weight?.index,
    'isSpecial': isSpecial,
    'addKeys': addKeys,
    'subKeys': subKeys,
  };
  factory ErpColumn.fromJson(Map<String, dynamic> json) => ErpColumn(
    key: json['key'],
    label: json['label'],
    width: (json['width'] as num).toDouble(),
    isFixed: json['isFixed'] ?? false,
    isVisible: json['isVisible'] ?? true,
    align: TextAlign.values[json['align'] ?? 0],
    weight: json['weight'] != null ? FontWeight.values[json['weight']] : null,
    isSpecial: json['isSpecial'] ?? false,
    addKeys: json['addKeys'] != null
        ? List<String>.from(json['addKeys'])
        : null,
    subKeys: json['subKeys'] != null
        ? List<String>.from(json['subKeys'])
        : null,
  );
}

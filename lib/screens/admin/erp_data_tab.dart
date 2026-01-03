import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'package:excel/excel.dart' as excel_pkg; // Aliased
import '../../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../mixins/optimized_operations.dart';

import '../../widgets/global_data_sync.dart';
import 'dart:async';

class ErpDataTab extends StatefulWidget {
  const ErpDataTab({super.key});

  @override
  State<ErpDataTab> createState() => _ErpDataTabState();
}

class _ErpDataTabState extends State<ErpDataTab>
    with OptimizedOperations, WidgetsBindingObserver {
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  List<dynamic> _erpData = [];
  String _searchQuery = "";
  StreamSubscription? _refreshSub;
  String _selectedWarehouse = "Tất cả";
  List<String> _warehouses = ["Tất cả"];
  String _currentUsername = "";
  
  // Real-time Sync Progress state
  String _syncStatus = "";
  double _syncPercent = 0;
  bool _isSyncing = false;
  // Removed _selectedDate and _warehouseController from main state
  // as they are now local to the Sync Dialog.

  final ScrollController _horizontalController = ScrollController();
  final ScrollController _headerHorizontalController = ScrollController();
  final ScrollController _scrollableVerticalController = ScrollController();
  final ScrollController _fixedVerticalController = ScrollController();

  bool _isSyncingScroll = false;

  // Dynamic Columns Configuration
  late List<ErpColumn> _columns;
  List<String> _ignoredCols = [];

  // Hover state for crosshair highlighting
  int? _hoveredRowIndex;
  String? _hoveredColumnKey;

  @override
  void initState() {
    super.initState();
    _initColumns();
    _loadWarehouses();
    _currentUsername = context.read<AuthProvider>().currentUser?.username ?? "";
    _loadColumnConfig().then((_) => _loadLocalData());

    // Sync horizontal header with horizontal body
    _horizontalController.addListener(() {
      if (_headerHorizontalController.hasClients) {
        _headerHorizontalController.jumpTo(_horizontalController.offset);
      }
    });

    // Vertical sync logic
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

    // Listen for real-time updates via GlobalDataSync
    _refreshSub = GlobalDataSync.onRefresh.listen((category) {
      if (mounted &&
          (category.contains('erp') ||
              category.contains('audit') ||
              category == 'general')) {
        _loadLocalData();
      }
    });

    // Listen for real-time sync progress via Socket.IO
    _apiService.socket?.on('erp_sync_progress', (data) {
      if (mounted) {
        setState(() {
          _syncStatus = data['status'] ?? "";
          _syncPercent = (data['percent'] ?? 0.0).toDouble();
          _isSyncing = _syncPercent < 1.0;
        });
      }
    });

    WidgetsBinding.instance.addObserver(this);
  }

  void _initColumns() {
    _columns = [
      ErpColumn(key: 'stt', label: 'STT', width: 50, isFixed: true),
      ErpColumn(key: 'sku', label: 'Code', width: 140, isFixed: true),
      ErpColumn(key: 'sku_plain', label: 'Mã liền', width: 130, isFixed: true),

      ErpColumn(
        key: 'name',
        label: 'Tên vật tư',
        width: 220,
        isFixed: true,
        align: TextAlign.left,
      ),
      ErpColumn(key: 'warehouse', label: 'Kho', width: 60),
      ErpColumn(key: 'quantity', label: 'Qty(ERP)', width: 90),
      ErpColumn(key: 'kk1', label: 'KK1', width: 65),
      ErpColumn(key: 'kk2', label: 'KK2', width: 65),
      ErpColumn(key: 'kk3', label: 'KK3', width: 65),
      ErpColumn(key: 'kk4', label: 'KK4', width: 65),
      ErpColumn(key: 'kk5', label: 'KK5', width: 65),
      ErpColumn(key: 'kk6', label: 'KK6', width: 65),
      ErpColumn(key: 'kk7', label: 'KK7', width: 65),
      ErpColumn(key: 'kk8', label: 'KK8', width: 65),
      ErpColumn(key: 'kk9', label: 'KK9', width: 65),
      ErpColumn(key: 'kk10', label: 'KK10', width: 65),
      ErpColumn(
        key: 'total_kk',
        label: 'Tổng KK',
        width: 90,
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
        width: 100,
        weight: FontWeight.bold,
        addKeys: ['total_kk'],
        subKeys: ['quantity'],
      ),
      ErpColumn(key: 'merge_diff', label: 'CL NN', width: 110, isSpecial: true),
      ErpColumn(
        key: 'packing_diff',
        label: 'Packing/Bù',
        width: 200,
        align: TextAlign.left,
      ),
      ErpColumn(key: 're_audit', label: 'Kiểm lại', width: 80, isSpecial: true),
      ErpColumn(key: 'actions', label: 'Xóa', width: 60, isSpecial: true),
    ];
  }

  Future<void> _loadColumnConfig() async {
    final prefs = await SharedPreferences.getInstance();

    // Load Ignored List (Legacy or kept for explicit deletions)
    // _ignoredCols = prefs.getStringList('ignored_erp_cols') ?? [];
    // Actually we can merge concepts. If we save the full list, "Ignored" is just "Not in List".
    // But for Dynamic Columns, if they are not in the list, how do we know if they are "New" or "Deleted"?
    // So we STILL need _ignoredCols.

    _ignoredCols = prefs.getStringList('ignored_erp_cols') ?? [];

    final String? jsonStr = prefs.getString('erp_column_config');
    if (jsonStr != null) {
      try {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        final List<ErpColumn> loaded = decoded
            .map((e) => ErpColumn.fromJson(e))
            .toList();

        // Migration: ensure STT and SKU_PLAIN exist if they were newly added to the codebase
        if (!loaded.any((c) => c.key == 'stt')) {
          loaded.insert(
            0,
            ErpColumn(key: 'stt', label: 'STT', width: 50, isFixed: true),
          );
        }

        if (!loaded.any((c) => c.key == 'sku_plain')) {
          // Find index of 'sku' and insert after
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

        bool listChanged = false;

        // Ensure actions column exists
        if (!loaded.any((c) => c.key == 'actions')) {
          loaded.add(ErpColumn(key: 'actions', label: 'Xóa', width: 60, isSpecial: true));
          listChanged = true;
        }

        // Ensure re_audit column exists (backward compat)
        if (!loaded.any((c) => c.key == 're_audit')) {
            int actionsIdx = loaded.indexWhere((c) => c.key == 'actions');
            if (actionsIdx != -1) {
                loaded.insert(actionsIdx, ErpColumn(key: 're_audit', label: 'Kiểm lại', width: 80, isSpecial: true));
            } else {
                loaded.add(ErpColumn(key: 're_audit', label: 'Kiểm lại', width: 80, isSpecial: true));
            }
            listChanged = true;
        }

        setState(() {
          _columns = loaded;
          if (listChanged) _saveColumnConfig();
        });
      } catch (e) {
        debugPrint('Error loading column config: $e');
      }
    }
  }

  Future<void> _saveColumnConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonStr = jsonEncode(_columns.map((e) => e.toJson()).toList());
    await prefs.setString('erp_column_config', jsonStr);

    // Also save ignored
    await prefs.setStringList('ignored_erp_cols', _ignoredCols);
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _headerHorizontalController.dispose();
    _fixedVerticalController.dispose();
    _scrollableVerticalController.dispose();
    // _warehouseController.dispose();
    _refreshSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadLocalData();
    }
  }

  Future<void> _loadWarehouses() async {
    try {
      final list = await _apiService.getErpWarehouses();
      if (mounted) {
        setState(() {
          _warehouses = ["Tất cả", ...list];
        });
      }
    } catch (e) {
      debugPrint('Load warehouses error: $e');
    }
  }

  Future<void> _loadLocalData() async {
    setState(() => _isLoading = true);
    try {
      final data = await _apiService.getErpStockFromDb(
        warehouse: _selectedWarehouse == "Tất cả" ? "" : _selectedWarehouse,
      );
      // Process dynamic columns
      final Set<String> dynamicKeys = {};

      for (var item in data) {
        if (item['custom_data'] != null) {
          try {
            dynamic cd = item['custom_data'];
            Map<String, dynamic> customMap = {};
            if (cd is String) {
              // Handle potential "null" string or empty
              if (cd != 'null' && cd.isNotEmpty) {
                customMap = jsonDecode(cd);
              }
            } else if (cd is Map) {
              customMap = Map<String, dynamic>.from(cd);
            }

            customMap.forEach((k, v) {
              item[k] = v; // Flatten into main map
              if (!_ignoredCols.contains(k)) {
                dynamicKeys.add(k);
              }
            });
          } catch (e) {
            debugPrint('Error parsing custom_data: $e');
          }
        }

        // Ensure merged_skus is a parsed List for easier logic later
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

      // Re-initialize columns and inject dynamic ones
      if (mounted) {
        if (_columns.isEmpty) {
          _initColumns();
          await _loadColumnConfig(); // Load saved config if first time
        }

        // Identify which dynamic keys are already in _columns
        final currentKeys = _columns.map((c) => c.key).toSet();

        // Insert after 'name' (index 1: sku=0, name=1) -> Insert at 2
        int insertIndex = 2;
        // Sort keys for consistency
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

      setState(() => _erpData = data);
    } catch (e) {
      debugPrint('Load local data error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showSyncDialog() async {
    DateTime selectedDate = DateTime.now();
    final TextEditingController whCtrl = TextEditingController(text: "F02");

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Cập nhật dữ liệu ERP (Cào web)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => selectedDate = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Ngày lịch trình',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(DateFormat('dd/MM/yyyy').format(selectedDate)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: whCtrl,
                decoration: const InputDecoration(
                  labelText: 'Kho',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.warehouse),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _fetchErpData(
                  DateFormat('yyyy/MM/dd').format(selectedDate),
                  whCtrl.text.trim(),
                );
              },
              child: const Text('Bắt đầu lấy dữ liệu'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchErpData(String dateVal, String warehouseVal) async {
    setState(() {
      _isLoading = true;
      _isSyncing = true;
      _syncStatus = "Đang bắt đầu...";
      _syncPercent = 0.01;
    });
    try {
      final result = await _apiService.syncErpStockData(
        date: dateVal,
        warehouse: warehouseVal,
      );
      if (result != null && result['data'] != null) {
        setState(() => _erpData = result['data']);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã cập nhật ${result['count']} bản ghi')),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );
    if (result != null) {
      setState(() => _isLoading = true);
      try {
        dynamic file;
        if (kIsWeb) {
          file = result.files.single.bytes;
        } else {
          file = File(result.files.single.path!);
        }

        final res = await _apiService.uploadErpExcel(
          file,
          '', // Warehouse
        );
        if (res != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Upload Excel thành công: ${res['count']}'),
              ),
            );
          }
          _loadLocalData();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Lỗi upload Excel')));
          }
        }
      } catch (e) {
        debugPrint('Upload Excel error: $e');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _isLoading = true);
    try {
      final excel = excel_pkg.Excel.createExcel();
      // Rename default sheet
      final sheetName = 'ERP Data';
      excel.rename('Sheet1', sheetName);
      final sheet = excel[sheetName];

      // Get visible columns
      final visibleCols = _columns.where((c) => c.isVisible).toList();

      // Headers
      for (int i = 0; i < visibleCols.length; i++) {
        final col = visibleCols[i];
        final cell = sheet.cell(
          excel_pkg.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
        );
        cell.value = excel_pkg.TextCellValue(col.label);

        final style = excel_pkg.CellStyle(
          bold: true,
          horizontalAlign: excel_pkg.HorizontalAlign.Center,
          verticalAlign: excel_pkg.VerticalAlign.Center,
          topBorder: excel_pkg.Border(borderStyle: excel_pkg.BorderStyle.Thin),
          bottomBorder: excel_pkg.Border(
            borderStyle: excel_pkg.BorderStyle.Thin,
          ),
          leftBorder: excel_pkg.Border(borderStyle: excel_pkg.BorderStyle.Thin),
          rightBorder: excel_pkg.Border(
            borderStyle: excel_pkg.BorderStyle.Thin,
          ),
          backgroundColorHex: excel_pkg.ExcelColor.fromHexString('#CCCCCC'),
        );
        cell.cellStyle = style;
      }

      // Filtered Data
      final displayList = _erpData.where((item) {
        final query = _searchQuery.toLowerCase();
        return (item['sku'] ?? '').toString().toLowerCase().contains(query) ||
            (item['name'] ?? '').toString().toLowerCase().contains(query);
      }).toList();

      // Tracking max width for each column
      List<double> maxContentLengths = List.filled(visibleCols.length, 10.0);

      // Rows
      for (int r = 0; r < displayList.length; r++) {
        final item = displayList[r];
        for (int c = 0; c < visibleCols.length; c++) {
          final col = visibleCols[c];
          final cell = sheet.cell(
            excel_pkg.CellIndex.indexByColumnRow(
              columnIndex: c,
              rowIndex: r + 1,
            ),
          );

          dynamic val;
          if (col.key == 'stt') {
            val = r + 1;
          } else if (col.key == 'diff' || col.key == 'total_kk') {
            final d = _calculateFormulaValue(col, item);
            val = (d % 1 == 0) ? d.toInt() : d;
          } else if (col.key == 'merge_diff') {
            // Logic for vertical merging in Excel
            bool isFirstInContiguousGroup = true;
            String groupKey = "";
            if (item['merged_skus'] is List) {
              final ms = List<String>.from(
                (item['merged_skus'] as List).map((e) => e.toString().trim()),
              );
              if (ms.length > 1) {
                ms.sort();
                groupKey = ms.join('|');
              }
            }

            if (groupKey.isNotEmpty && r > 0) {
              final prevItem = displayList[r - 1];
              String pgk = "";
              if (prevItem['merged_skus'] is List) {
                final pms = List<String>.from(
                  (prevItem['merged_skus'] as List).map(
                    (e) => e.toString().trim(),
                  ),
                );
                if (pms.length > 1) {
                  pms.sort();
                  pgk = pms.join('|');
                }
              }
              if (pgk == groupKey) isFirstInContiguousGroup = false;
            }

            if (isFirstInContiguousGroup) {
              final raw = item['diff_nn'];
              final double? d = double.tryParse(raw?.toString() ?? '');
              if (d != null && d != 0) {
                val = (d % 1 == 0) ? d.toInt() : d;
              } else {
                val = '';
              }
            } else {
              val = '';
            }
          } else {
            final raw = item[col.key];
            if (col.key.startsWith('kk') || col.key == 'packing_diff') {
              final double? d = double.tryParse(raw?.toString() ?? '');
              if (d != null && d != 0) {
                val = (d % 1 == 0) ? d.toInt() : d;
              } else {
                val = '';
              }
            } else if (col.key == 'quantity') {
              final double? d = double.tryParse(raw?.toString() ?? '');
              if (d != null) {
                val = (d % 1 == 0) ? d.toInt() : d;
              } else {
                val = raw?.toString() ?? '';
              }
            } else {
              val = raw?.toString() ?? '';
              if (val == '0' || val == '0.0') val = '';
            }
          }

          if (val is num) {
            cell.value = val is int
                ? excel_pkg.IntCellValue(val)
                : excel_pkg.DoubleCellValue(val.toDouble());
          } else {
            cell.value = excel_pkg.TextCellValue(val.toString());
          }

          // Track length
          String vStr = val.toString();
          if (vStr.length.toDouble() > maxContentLengths[c]) {
            maxContentLengths[c] = vStr.length.toDouble();
          }

          cell.cellStyle = excel_pkg.CellStyle(
            horizontalAlign: excel_pkg.HorizontalAlign.Center,
            verticalAlign: excel_pkg.VerticalAlign.Center,
            topBorder: excel_pkg.Border(
              borderStyle: excel_pkg.BorderStyle.Thin,
            ),
            bottomBorder: excel_pkg.Border(
              borderStyle: excel_pkg.BorderStyle.Thin,
            ),
            leftBorder: excel_pkg.Border(
              borderStyle: excel_pkg.BorderStyle.Thin,
            ),
            rightBorder: excel_pkg.Border(
              borderStyle: excel_pkg.BorderStyle.Thin,
            ),
          );
        }
      }

      // Set column widths manually based on max content
      for (int i = 0; i < visibleCols.length; i++) {
        // Simple heuristic: content length * 1.2 + offset for padding
        sheet.setColumnWidth(i, maxContentLengths[i] * 1.2 + 5);
      }

      // Post-process: Merging 'CL NN' cells in Excel
      int mergeDiffColIdx = visibleCols.indexWhere(
        (c) => c.key == 'merge_diff',
      );
      if (mergeDiffColIdx != -1) {
        int startRowIdx = -1;
        String currentGroupKey = "";

        for (int r = 0; r < displayList.length; r++) {
          final item = displayList[r];
          String groupKey = "";
          if (item['merged_skus'] is List) {
            final ms = List<String>.from(
              (item['merged_skus'] as List).map((e) => e.toString().trim()),
            );
            if (ms.length > 1) {
              ms.sort();
              groupKey = ms.join('|');
            }
          }

          if (groupKey.isNotEmpty && groupKey == currentGroupKey) {
            // Contiguous group continues
            if (r == displayList.length - 1) {
              // End of list, merge from startRowIdx to current r
              sheet.merge(
                excel_pkg.CellIndex.indexByColumnRow(
                  columnIndex: mergeDiffColIdx,
                  rowIndex: startRowIdx + 1,
                ),
                excel_pkg.CellIndex.indexByColumnRow(
                  columnIndex: mergeDiffColIdx,
                  rowIndex: r + 1,
                ),
              );
            }
          } else {
            // Group ended or changed
            if (startRowIdx != -1 && (r - 1) > startRowIdx) {
              sheet.merge(
                excel_pkg.CellIndex.indexByColumnRow(
                  columnIndex: mergeDiffColIdx,
                  rowIndex: startRowIdx + 1,
                ),
                excel_pkg.CellIndex.indexByColumnRow(
                  columnIndex: mergeDiffColIdx,
                  rowIndex: r, // (r-1) + 1
                ),
              );
            }

            if (groupKey.isNotEmpty) {
              startRowIdx = r;
              currentGroupKey = groupKey;
            } else {
              startRowIdx = -1;
              currentGroupKey = "";
            }
          }
        }
      }

      // Export
      String? outputFile;
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Lưu file Excel',
          fileName:
              'ERP_Export_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.xlsx',
          allowedExtensions: ['xlsx'],
        );
      } else {
        // Mobile fallback? For now focus on Desktop per user env
        // But logic is generic enough.
      }

      if (outputFile != null) {
        if (!outputFile.endsWith('.xlsx'))
          outputFile += '.xlsx'; // Ensure extension

        var fileBytes = excel.save();
        if (fileBytes != null) {
          final File f = File(outputFile);
          // No directory check needed if saveFile returns valid path
          f.createSync(recursive: true);
          f.writeAsBytesSync(fileBytes);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Xuất file thành công: $outputFile'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Export Excel error: $e');
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadDynamicExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );
    if (result != null) {
      setState(() => _isLoading = true);
      try {
        dynamic file;
        if (kIsWeb) {
          file = result.files.single.bytes;
        } else {
          file = File(result.files.single.path!);
        }

        final res = await _apiService.uploadDynamicColumnsExcel(file);
        if (mounted) setState(() => _isLoading = false);

        if (res != null) {
          final success = res['successCount'] ?? 0;
          final fail = res['failCount'] ?? 0;
          final List<dynamic> details = res['failedDetails'] ?? [];

          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Kết quả tải lên Cột Động'),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hoàn thành: $success dòng',
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Thất bại: $fail dòng',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Chi tiết lỗi:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Divider(),
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                        ),
                        child: ListView.builder(
                          itemCount: details.length,
                          itemBuilder: (c, i) => ListTile(
                            dense: true,
                            title: Text('${details[i]['sku']}'),
                            subtitle: Text(
                              '${details[i]['reason']}',
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Đóng'),
                ),
              ],
            ),
          );

          if (success > 0) _loadLocalData();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Lỗi upload Cột Động')),
            );
          }
        }
      } catch (e) {
        debugPrint('Upload Dynamic Excel error: $e');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildSummaryItemPremium(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.8), size: 14),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: Colors.white.withOpacity(0.8),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
      ],
    );
  }

  Future<void> _requestReAudit(Map<String, dynamic> item) async {
    final sku = item['sku']?.toString() ?? 'N/A';
    final warehouse = item['warehouse']?.toString() ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yêu cầu kiểm lại'),
        content: Text('Gửi yêu cầu kiểm lại cho mã $sku?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Gửi yêu cầu'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        final diffNn = item['diff_nn']?.toString() ?? '';
        final diffVal = (diffNn.isNotEmpty && diffNn != '0' && diffNn != '-')
            ? diffNn
            : (item['difference']?.toString() ?? '0');

        final success = await _apiService.sendNotification(
          message:
              'Yêu cầu kiểm lại mã: $sku (Kho: $warehouse) | Lệch: $diffVal',
          type: 'WARNING',
          sender: 'Admin',
          metadata: {
            'action': 'RE_AUDIT',
            'sku': sku,
            'warehouse': warehouse,
            'diff': diffVal,
          },
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success
                    ? 'Đã gửi yêu cầu kiểm lại mã $sku'
                    : 'Lỗi khi gửi yêu cầu',
              ),
              backgroundColor: success ? Colors.green : Colors.red,
            ),
          );
        }
      } catch (e) {
        debugPrint('Request re-audit error: $e');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _confirmDelete(dynamic item) async {
    final sku = item['sku'];
    final id = item['id'];

    if (id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa mã $sku này không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (mounted) setState(() => _isLoading = true);
      final success = await _apiService.deleteErpStock(id);
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Đã xóa thành công')));
          _loadLocalData();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Xóa thất bại')));
        }
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // _selectDate logic moved to _showSyncDialog
  // void _selectDate...

  void _showMergeDiffDialog(Map<String, dynamic> currentItem) {
    final currentSku = currentItem['sku']?.toString() ?? '';
    final currentWarehouse = currentItem['warehouse']?.toString() ?? '';
    final filteredData = _erpData.where((item) {
      final query = _searchQuery.toLowerCase();
      return (item['sku'] ?? '').toString().toLowerCase().contains(query) ||
          (item['name'] ?? '').toString().toLowerCase().contains(query);
    }).toList();
    final currentIndex = filteredData.indexWhere(
      (item) => item['sku']?.toString() == currentSku,
    );
    if (currentIndex == -1) return;
    final relatedItems = filteredData.sublist(
      (currentIndex - 5).clamp(0, filteredData.length),
      (currentIndex + 6).clamp(0, filteredData.length),
    );

    // Trim current SKU for consistency
    final trimCurrentSku = currentSku.trim();

    // Find the 'diff' column to calculate values consistently with the table
    final diffCol = _columns.firstWhere(
      (c) => c.key == 'diff',
      orElse: () => ErpColumn(key: 'diff', label: '', width: 0),
    );

    // Restore previous selection from DB with Trimming
    final selectedSkus = <String>{};
    final savedMerged = currentItem['merged_skus'];
    if (savedMerged != null) {
      if (savedMerged is List) {
        selectedSkus.addAll(savedMerged.map((e) => e.toString().trim()));
      } else if (savedMerged is String && savedMerged.startsWith('[')) {
        try {
          final List<dynamic> decoded = jsonDecode(savedMerged);
          selectedSkus.addAll(decoded.map((e) => e.toString().trim()));
        } catch (e) {
          debugPrint('Decode merged_skus error: $e');
        }
      }
    }
    // If empty but diff_nn exists, at least select itself (legacy compatibility)
    if (selectedSkus.isEmpty) selectedSkus.add(trimCurrentSku);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final totalDiff = _erpData
              .where((item) {
                // Normalize SKU during search
                final itemSku = item['sku']?.toString().trim() ?? '';
                return selectedSkus.contains(itemSku);
              })
              .fold<double>(0, (sum, item) {
                // Use the formula calculator to match the table exactly
                final val = _calculateFormulaValue(diffCol, item);
                return sum + val;
              });

          return AlertDialog(
            title: Text('Ghép chênh lệch cho: $trimCurrentSku'),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Chọn các mã để ghép chênh lệch:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(
                    height: 300,
                    child: ListView.builder(
                      itemCount: relatedItems.length,
                      itemBuilder: (context, index) {
                        final item = relatedItems[index];
                        // Normalize SKU here too
                        final sku = item['sku']?.toString().trim() ?? '';
                        // Calculate display value
                        final diffVal = _calculateFormulaValue(diffCol, item);

                        return CheckboxListTile(
                          dense: true,
                          title: Text(
                            sku,
                            style: TextStyle(
                              fontWeight: sku == trimCurrentSku
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: sku == trimCurrentSku
                                  ? Colors.blue
                                  : Colors.black,
                            ),
                          ),
                          subtitle: Text(
                            '${item['name']} | CL: ${diffVal.toStringAsFixed(0)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          value: selectedSkus.contains(sku),
                          onChanged: (val) {
                            setDialogState(() {
                              if (val == true) {
                                selectedSkus.add(sku);
                              } else {
                                selectedSkus.remove(sku);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const Divider(),
                  Text(
                    'Tổng CL NN: ${totalDiff > 0 ? '+' : ''}${totalDiff.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: totalDiff < 0
                          ? Colors.red
                          : (totalDiff > 0 ? Colors.green : Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Hủy'),
              ),
              ElevatedButton(
                onPressed: () async {
                  // if (selectedSkus.isEmpty) return; // Allow clear
                  if (await _apiService.updateErpDiffNn(
                    currentSku,
                    totalDiff.toString(),
                    warehouse: currentWarehouse,
                    mergedSkus: selectedSkus.toList(),
                  )) {
                    Navigator.pop(context);
                    _loadLocalData();
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

  void _showPackingDialog() {
    TextEditingController? skuInputCtrl;
    FocusNode? skuFocusNode;
    final TextEditingController noteController = TextEditingController();

    // Local state for feedback
    String? statusMsg;
    Color statusColor = Colors.green;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> submit() async {
            final sku = skuInputCtrl?.text.trim();
            final note = noteController.text.trim();

            if (sku == null || sku.isEmpty) {
              setDialogState(() {
                statusMsg = 'Vui lòng nhập SKU';
                statusColor = Colors.red;
              });
              return;
            }

            // Find warehouse for this SKU
            final item = _erpData.firstWhere(
              (i) => i['sku']?.toString() == sku,
              orElse: () => {},
            );
            final wh = item['warehouse']?.toString() ?? '';

            // Call API
            // Note: Update existing API service if needed to return bool success
            // Assuming logic:
            final success = await _apiService.updateErpPackingNote(
              sku,
              note,
              warehouse: wh,
            );

            if (success) {
              setDialogState(() {
                statusMsg = 'Đã lưu: $sku ($note)';
                statusColor = Colors.green;
              });

              // Determine if we should clear fields. User wants to enter NEXT one.
              skuInputCtrl?.clear();
              noteController.clear();

              // Refocus SKU
              skuFocusNode?.requestFocus();

              // Refresh background data
              _loadLocalData();
            } else {
              setDialogState(() {
                statusMsg = 'Lỗi khi lưu $sku';
                statusColor = Colors.red;
              });
            }
          }

          return AlertDialog(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nhập Packing/Bù hàng'),
                if (statusMsg != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      statusMsg!,
                      style: TextStyle(
                        fontSize: 13,
                        color: statusColor,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Autocomplete<String>(
                    optionsBuilder: (v) => v.text.isEmpty
                        ? const Iterable<String>.empty()
                        : _erpData
                              .where(
                                (i) => (i['sku'] ?? '')
                                    .toString()
                                    .toLowerCase()
                                    .contains(v.text.toLowerCase()),
                              )
                              .map((i) => i['sku']?.toString() ?? ''),
                    onSelected: (v) {
                      skuInputCtrl?.text = v;
                    },
                    fieldViewBuilder: (ctx, ctrl, f, onS) {
                      skuInputCtrl = ctrl;
                      skuFocusNode = f;
                      return TextField(
                        controller: ctrl,
                        focusNode: f,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Mã số (SKU)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.qr_code),
                        ),
                        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4.0,
                          child: SizedBox(
                            width: 300,
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (BuildContext context, int index) {
                                final String option = options.elementAt(index);
                                return ListTile(
                                  title: Text(option),
                                  onTap: () => onSelected(option),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: noteController,
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => submit(),
                    decoration: const InputDecoration(
                      labelText: 'Nội dung',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.note),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Mẹo: Nhập xong nhấn Enter để lưu',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đóng'),
              ),
              ElevatedButton(
                onPressed: submit,
                child: const Text('Lưu & Tiếp'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_columns.isEmpty) return const Center(child: CircularProgressIndicator());

    final filtered = _erpData.where((item) {
      final q = _searchQuery.toLowerCase();
      final sku = (item['sku'] ?? '').toString().toLowerCase();
      final name = (item['name'] ?? '').toString().toLowerCase();
      final sku_plain = (item['sku_plain'] ?? '').toString().toLowerCase();
      final matchesSearch = sku.contains(q) || name.contains(q) || sku_plain.contains(q);

      final matchesWarehouse =
          _selectedWarehouse == "Tất cả" ||
          (item['warehouse'] ?? '').toString() == _selectedWarehouse;

      return matchesSearch && matchesWarehouse;
    }).toList();

    // Calculate Summary
    int totalSkus = filtered.length;
    double totalQty = 0;
    double totalKk = 0;
    for (var item in filtered) {
      totalQty += _parseSafe(item['quantity']);
      totalKk += _calculateFormulaValue(
        _columns.firstWhere((c) => c.key == 'total_kk'),
        item,
      );
    }

    final currencyFormat = NumberFormat("#,###.##", "en_US");

    return Column(
      children: [
        if (_isSyncing) _buildSyncProgress(),
        _buildFiltersTab(),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            children: [
              // Summary Section - Rebuilt for Premium Look
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue[800]!, Colors.blue[600]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildSummaryItemPremium(
                        "TỔNG MÃ SỐ",
                        "$totalSkus",
                        Icons.inventory_2_outlined,
                      ),
                    ),
                    Container(
                      height: 40,
                      width: 1,
                      color: Colors.white.withOpacity(0.3),
                    ),
                    Expanded(
                      child: _buildSummaryItemPremium(
                        "TỔNG QTY (ERP)",
                        currencyFormat.format(totalQty),
                        Icons.analytics_outlined,
                      ),
                    ),
                    Container(
                      height: 40,
                      width: 1,
                      color: Colors.white.withOpacity(0.3),
                    ),
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
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _showSyncDialog,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync, size: 18),
                    label: const Text(
                      'Cập nhật',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  // Import Excel Button
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _uploadExcel,
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text(
                      'Nhập Excel',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  // New Export Excel Button
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _exportExcel,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text(
                      'Xuất Excel',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _uploadDynamicExcel,
                    icon: const Icon(Icons.playlist_add, size: 18),
                    label: const Text(
                      'Cột động',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _showPackingDialog,
                    icon: const Icon(Icons.note_add, size: 18),
                    label: const Text(
                      'Nhập Packing',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _showColumnConfig,
                    icon: const Icon(Icons.view_column_rounded, size: 18),
                    label: const Text(
                      'Tùy chỉnh cột',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      backgroundColor: Colors.blueGrey,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading && _erpData.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
              ? _buildEmpty()
              : _buildTable(filtered),
        ),
      ],
    );
  }

  Widget _buildFiltersTab() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_list, size: 20, color: Colors.blueGrey),
          const SizedBox(width: 12),
          const Text(
            'Kho:',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
          ),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: _selectedWarehouse,
            underline: const SizedBox(),
            items: _warehouses.map((w) {
              return DropdownMenuItem(
                value: w,
                child: Text(w, style: const TextStyle(fontSize: 14)),
              );
            }).toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() => _selectedWarehouse = v);
                _loadLocalData();
              }
            },
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildSyncProgress() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.blue[50],
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Đang đồng bộ ERP: $_syncStatus',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
              Text(
                '${(_syncPercent * 100).toInt()}%',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _syncPercent,
            backgroundColor: Colors.blue[100],
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.cloud_off, size: 64, color: Colors.grey[300]),
        const SizedBox(height: 16),
        Text(
          _erpData.isEmpty ? 'Chưa có dữ liệu ERP' : 'Không tìm thấy kết quả',
          style: TextStyle(color: Colors.grey[600]),
        ),
      ],
    ),
  );

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
                  _saveColumnConfig(); // SAVE
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
                  _buildFormulaSelector("Cộng (+)", tempAddKeys, (keys) {
                    setEditState(() => tempAddKeys = keys);
                  }),
                  const SizedBox(height: 8),
                  _buildFormulaSelector("Trừ (-)", tempSubKeys, (keys) {
                    setEditState(() => tempSubKeys = keys);
                  }),
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
                    _saveColumnConfig(); // SAVE
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
                if (val) {
                  newList.add(c.key);
                } else {
                  newList.remove(c.key);
                }
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

  void _showColumnConfig() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Cấu hình bảng"),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _initColumns();
                          _saveColumnConfig();
                        });
                        setDialogState(() {});
                      },
                      icon: const Icon(Icons.restore),
                      label: const Text("Mặc định"),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _addColumnDialog();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text("Thêm"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
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
                          _saveColumnConfig(); // SAVE
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
                                    _saveColumnConfig(); // SAVE
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
                                    _saveColumnConfig(); // SAVE
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
                                    _saveColumnConfig(); // SAVE and Persist Deletion
                                  });
                                  setDialogState(() {}); // Refresh dialog
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

  Widget _buildTable(List<dynamic> data) {
    if (data.isEmpty) return const SizedBox.shrink();

    // 1. Calculate Totals
    final Map<String, double> totals = {};
    for (var item in data) {
      for (var col in _columns) {
        // Skip text columns from summation
        if (col.key != 'sku' &&
            col.key != 'sku_plain' &&
            col.key != 'name' &&
            col.key != 'warehouse' &&
            col.key != 're_audit' &&
            col.key != 'stt' &&
            col.key != 'merge_diff') {
          double val = _calculateFormulaValue(col, item);
          totals[col.key] = (totals[col.key] ?? 0) + val;
        }
      }
    }

    // 2. Create Total Row
    final totalItem = {
      'sku': 'TỔNG CỘNG',
      'name': '',
      'warehouse': '',
      'is_total_row': true,
      ...totals,
    };

    // 3. Combine data + total
    final displayList = [...data, totalItem];

    // 4. Split columns
    final visibleCols = _columns.where((c) => c.isVisible).toList();
    final fixedCols = visibleCols.where((c) => c.isFixed).toList();
    final scrollableCols = visibleCols.where((c) => !c.isFixed).toList();

    double fixedWidth = fixedCols.fold(0, (sum, c) => sum + c.width);
    double scrollWidth = scrollableCols.fold(0, (sum, c) => sum + c.width);

    return Row(
      children: [
        // FIXED COLUMNS
        if (fixedCols.isNotEmpty)
          SizedBox(
            width: fixedWidth,
            child: Column(
              children: [
                // Header
                Container(
                  color: Colors.blueGrey[50],
                  height: 34,
                  child: Row(
                    children: fixedCols
                        .map(
                          (c) => _cell(c.label, c.width, true, align: c.align),
                        )
                        .toList(),
                  ),
                ),
                const Divider(height: 1, thickness: 1),
                // Body
                Expanded(
                  child: ListView.builder(
                    controller: _fixedVerticalController,
                    itemCount: displayList.length,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    cacheExtent: 500,
                    itemBuilder: (context, index) {
                      final item = displayList[index];
                      final isTotal = item['is_total_row'] == true;
                      final rowColor = isTotal
                          ? Colors.orange[100]!
                          : (index % 2 == 0
                                ? Colors.white
                                : Colors.grey[50]!.withOpacity(0.5));

                      return RepaintBoundary(
                        child: SizedBox(
                          height: 34,
                          child: Row(
                            children: fixedCols
                                .map(
                                  (c) => _renderDataCell(
                                    c,
                                    item,
                                    index,
                                    displayList,
                                    rowColor,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

        // SCROLLABLE COLUMNS
        Expanded(
          child: Column(
            children: [
              // Header
              SingleChildScrollView(
                controller: _headerHorizontalController,
                scrollDirection: Axis.horizontal,
                physics:
                    const NeverScrollableScrollPhysics(), // Synced via listener
                child: Container(
                  color: Colors.blueGrey[50],
                  width: scrollWidth,
                  height: 34,
                  child: Row(
                    children: scrollableCols
                        .map(
                          (c) => _cell(c.label, c.width, true, align: c.align),
                        )
                        .toList(),
                  ),
                ),
              ),
              const Divider(height: 1, thickness: 1),
              // Body
              Expanded(
                child: Scrollbar(
                  controller: _horizontalController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _horizontalController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: scrollWidth,
                      child: ListView.builder(
                        controller: _scrollableVerticalController,
                        itemCount: displayList.length,
                        addAutomaticKeepAlives:
                            false, // Don't keep offscreen widgets alive
                        addRepaintBoundaries: true, // Optimize repainting
                        cacheExtent: 500, // Limit cache to ~15 rows
                        itemBuilder: (context, index) {
                          final item = displayList[index];
                          final isTotal = item['is_total_row'] == true;
                          final rowColor = isTotal
                              ? Colors.orange[100]!
                              : (index % 2 == 0
                                    ? Colors.white
                                    : Colors.grey[50]!.withOpacity(0.5));

                          // Wrap each row in RepaintBoundary for better performance
                          return RepaintBoundary(
                            child: SizedBox(
                              height: 34,
                              child: Row(
                                children: scrollableCols
                                    .map(
                                      (c) => _renderDataCell(
                                        c,
                                        item,
                                        index,
                                        displayList,
                                        rowColor,
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          );
                        },
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

  double _calculateFormulaValue(ErpColumn col, dynamic item, {int depth = 0}) {
    if (depth > 5) return 0; // Prevent infinite recursion

    // If no formula, return raw value
    if ((col.addKeys == null || col.addKeys!.isEmpty) &&
        (col.subKeys == null || col.subKeys!.isEmpty)) {
      return _parseSafe(item[col.key]);
    }

    double result = 0;
    for (var k in col.addKeys ?? []) {
      final targetCol = _columns.firstWhere(
        (c) => c.key == k,
        orElse: () => ErpColumn(key: k, label: '', width: 0),
      );
      if (targetCol.label.isEmpty) {
        // Fallback to raw data if key not in columns
        result += _parseSafe(item[k]);
      } else {
        result += _calculateFormulaValue(targetCol, item, depth: depth + 1);
      }
    }
    for (var k in col.subKeys ?? []) {
      final targetCol = _columns.firstWhere(
        (c) => c.key == k,
        orElse: () => ErpColumn(key: k, label: '', width: 0),
      );
      if (targetCol.label.isEmpty) {
        result -= _parseSafe(item[k]);
      } else {
        result -= _calculateFormulaValue(targetCol, item, depth: depth + 1);
      }
    }
    return result;
  }

  double _parseSafe(dynamic v) {
    if (v == null) return 0;
    String s = v.toString().replaceAll(',', '');
    return double.tryParse(s) ?? 0;
  }

  Widget _renderDataCell(
    ErpColumn col,
    dynamic item,
    int rowIndex,
    List<dynamic> allData,
    Color rowColor,
  ) {
    bool isTotal = item['is_total_row'] == true;

    // Grouping logic
    String groupKey = "";
    if (!isTotal &&
        item['merged_skus'] != null &&
        item['merged_skus'] is List) {
      final ms = List<String>.from(
        (item['merged_skus'] as List).map((e) => e.toString().trim()),
      );
      if (ms.length > 1) {
        ms.sort();
        groupKey = ms.join('|');
      }
    }

    // Determine Highlight Color (ONLY Row highlighting, no more column highlighting)
    Color? cellBg = rowColor;
    if (!isTotal) {
      if (_hoveredRowIndex == rowIndex) {
        // Entire row gets a light highlight
        final highlight = Colors.blue.withOpacity(0.08);
        cellBg = Color.alphaBlend(highlight, rowColor);
      }
    }

    Widget cellWidget;
    if (col.key == 'merge_diff' && !isTotal) {
      bool isAdjacentBack = false;
      bool isAdjacentNext = false;
      bool isDisplayLeader = false;
      double verticalOffset = 0;

      if (groupKey.isNotEmpty) {
        // Find contiguous group bounds
        int contiguousStart = rowIndex;
        while (contiguousStart > 0) {
          final prevItem = allData[contiguousStart - 1];
          if (prevItem['is_total_row'] == true) break;
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
            isAdjacentBack = true;
          } else {
            break;
          }
        }

        int contiguousEnd = rowIndex;
        while (contiguousEnd < allData.length - 1) {
          final nextItem = allData[contiguousEnd + 1];
          if (nextItem['is_total_row'] == true) break;
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
            isAdjacentNext = true;
          } else {
            break;
          }
        }

        int count = contiguousEnd - contiguousStart + 1;
        // THE LAST ROW (contiguousEnd) is the Display Leader because it's drawn last,
        // avoiding being covered by subsequent row backgrounds.
        if (rowIndex == contiguousEnd) {
          isDisplayLeader = true;
          // Calculate offset to pull content back up to the visual center
          // Visual center of block is at (count * 34) / 2 from start.
          // Last row center is at (count - 1)*34 + 17 from start.
          // Offset = (count * 17) - (count * 34 - 17) = 17 - count * 17
          verticalOffset = (1.0 - count) * 17.0;
        }
      } else {
        isDisplayLeader = true;
      }

      cellWidget = _buildMergeCell(
        item,
        col.width,
        cellBg: cellBg,
        isDisplayLeader: isDisplayLeader,
        isAdjacentBack: isAdjacentBack,
        isAdjacentNext: isAdjacentNext,
        verticalOffset: verticalOffset,
      );
    } else if (col.key == 're_audit' && !isTotal) {
      cellWidget = _buildReAuditButton(item, col.width, cellBg: cellBg);
    } else if (col.key == 'actions' && !isTotal) {
      cellWidget = Container(
        width: col.width,
        height: 34,
        color: cellBg ?? Colors.transparent,
        alignment: Alignment.center,
        child: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red, size: 18),
          onPressed: () => _confirmDelete(item),
          tooltip: 'Xóa dòng này',
          padding: EdgeInsets.zero,
        ),
      );
    } else if (col.key == 'stt') {
      cellWidget = _cell(
        isTotal ? "" : (rowIndex + 1).toString(),
        col.width,
        false,
        align: col.align,
        cellBg: cellBg,
      );
    } else if (col.key == 'sku' && !isTotal) {
      String textValue = item[col.key]?.toString() ?? '';
      cellWidget = InkWell(
        onTap: () => _showMergeDiffDialog(item),
        child: _cell(
          textValue,
          col.width,
          false,
          align: col.align,
          weight: FontWeight.bold,
          color: Colors.blue,
          cellBg: cellBg,
        ),
      );
    } else if (col.key == 'sku' ||
        col.key == 'sku_plain' ||
        col.key == 'name' ||
        col.key == 'warehouse' ||
        (col.addKeys == null &&
            col.subKeys == null &&
            item[col.key] is String &&
            double.tryParse(item[col.key].toString()) == null)) {
      String textValue = item[col.key]?.toString() ?? '';
      cellWidget = _cell(
        textValue,
        col.width,
        false,
        align: col.align,
        weight: (col.key == 'sku' || isTotal) ? FontWeight.bold : col.weight,
        color: col.key == 'sku' ? Colors.blue : null,
        cellBg: cellBg,
      );
    } else if (isTotal) {
      double val = item[col.key] is double ? item[col.key] : 0.0;
      String display = val == val.toInt()
          ? val.toInt().toString()
          : val.toStringAsFixed(2);
      cellWidget = _cell(
        display,
        col.width,
        false,
        align: col.align,
        weight: FontWeight.bold,
        cellBg: cellBg,
      );
    } else {
      double numericValue = _calculateFormulaValue(col, item);
      String displayValue = numericValue == numericValue.toInt()
          ? numericValue.toInt().toString()
          : numericValue.toStringAsFixed(1);
      Color? textColor =
          col.key == 'diff' || (col.subKeys != null && col.subKeys!.isNotEmpty)
          ? (numericValue < 0
                ? Colors.red
                : (numericValue > 0 ? Colors.green : Colors.black))
          : null;
      cellWidget = _cell(
        displayValue,
        col.width,
        false,
        align: col.align,
        weight: col.weight,
        color: textColor,
        showZero: col.key == 'quantity',
        cellBg: cellBg,
      );

      // Make KK fields interactive
      if (col.key.startsWith('kk') &&
          !col.key.contains('total') &&
          !col.key.contains('diff')) {
        cellWidget = InkWell(
          onTap: () => _showEditKkDialog(item, col),
          child: cellWidget,
        );
      }
    }

    if (isTotal) return cellWidget;

    return MouseRegion(
      onEnter: (_) => setState(() {
        _hoveredRowIndex = rowIndex;
        _hoveredColumnKey = col.key;
      }),
      onExit: (_) => setState(() {
        _hoveredRowIndex = null;
        _hoveredColumnKey = null;
      }),
      child: cellWidget,
    );
  }

  Widget _cell(
    dynamic t,
    double w,
    bool h, {
    TextAlign align = TextAlign.center,
    Color? color,
    FontWeight? weight,
    bool showZero = true,
    Color? cellBg,
  }) {
    String text = t.toString().trim();
    if (!showZero && (text == '0' || text == '0.0' || text == '')) {
      text = '';
    }
    return Container(
      width: w,
      height: double.infinity,
      decoration: BoxDecoration(
        color: cellBg,
        border: Border(
          right: BorderSide(color: Colors.grey[300]!, width: 1),
          bottom: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: align == TextAlign.center
          ? Alignment.center
          : align == TextAlign.left
          ? Alignment.centerLeft
          : Alignment.centerRight,
      child: Text(
        text,
        style: TextStyle(
          fontWeight: h ? FontWeight.bold : weight,
          color: h ? Colors.black87 : color,
          fontSize: h ? 11 : 12,
        ),
        textAlign: align,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildMergeCell(
    Map<String, dynamic> item,
    double w, {
    Color? cellBg,
    bool isDisplayLeader = true,
    bool isAdjacentBack = false,
    bool isAdjacentNext = false,
    double verticalOffset = 0,
  }) {
    String dnn = item['diff_nn']?.toString() ?? '';
    double val = double.tryParse(dnn) ?? 0;

    // Format to remove .0 if it's an integer
    String displayDnn = "";
    if (val != 0) {
      displayDnn = val == val.toInt()
          ? val.toInt().toString()
          : val.toStringAsFixed(1);
    }

    Color textColor = Colors.grey;
    if (displayDnn.isNotEmpty) {
      if (val < 0) {
        textColor = Colors.red;
      } else if (val > 0) {
        textColor = Colors.green;
        if (!displayDnn.startsWith('+')) displayDnn = '+$displayDnn';
      } else {
        textColor = Colors.blue;
      }
    }

    return Container(
      width: w,
      height: double.infinity,
      clipBehavior: Clip.none, // CRITICAL: Allow overflow to draw on other rows
      decoration: BoxDecoration(
        color: cellBg,
        border: Border(
          right: BorderSide(color: Colors.grey[300]!, width: 1),
          // If there's a successor in the same group immediately below,
          // we hide the bottom border to "merge" the cells.
          bottom: isAdjacentNext
              ? BorderSide.none
              : BorderSide(color: Colors.grey[300]!, width: 1),
        ),
      ),
      alignment: Alignment.center,
      child: isDisplayLeader
          ? Transform.translate(
              offset: Offset(0, verticalOffset),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                decoration: BoxDecoration(
                  color: dnn.isNotEmpty ? textColor.withOpacity(0.1) : null,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item['merged_skus'] != null &&
                        (item['merged_skus'] as List).length > 1)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.check_box,
                          size: 14,
                          color: textColor,
                        ),
                      ),
                    Text(
                      displayDnn,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: displayDnn.isNotEmpty
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildReAuditButton(
    Map<String, dynamic> item,
    double w, {
    Color? cellBg,
  }) {
    return Container(
      width: w,
      height: double.infinity,
      decoration: BoxDecoration(
        color: cellBg,
        border: Border(
          right: BorderSide(color: Colors.grey[300]!, width: 1),
          bottom: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
      ),
      alignment: Alignment.center,
      child: IconButton(
        icon: const Icon(
          Icons.notification_important,
          color: Colors.orange,
          size: 18,
        ),
        onPressed: () => _requestReAudit(item),
        tooltip: 'Yêu cầu kiểm lại',
      ),
    );
  }

  void _showEditKkDialog(Map<String, dynamic> item, ErpColumn col) {
    final TextEditingController ctrl = TextEditingController(
      text: (item[col.key] ?? '0').toString(),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cập nhật ${col.label}: ${item['sku']}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Số lượng mới',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _updateKkValue(
                item['sku'],
                item['warehouse'] ?? '',
                col.key,
                ctrl.text.trim(),
              );
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateKkValue(
    String sku,
    String warehouse,
    String kkField,
    String value,
  ) async {
    final success = await safeUpdateErpStock(
      apiService: _apiService,
      sku: sku,
      warehouse: warehouse,
      updates: {kkField: value},
      userId: _currentUsername,
      showSnackbar: true,
    );

    if (success) {
      await _loadLocalData();
    }
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

  factory ErpColumn.fromJson(Map<String, dynamic> json) {
    return ErpColumn(
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
}

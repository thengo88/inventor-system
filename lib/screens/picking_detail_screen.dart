import 'package:flutter/material.dart';
import 'dart:io';
import 'package:excel/excel.dart' as excel;
import 'package:file_picker/file_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../models/picking_list.dart';
import '../services/api_service.dart';
import '../providers/picking_provider.dart';
import '../providers/auth_provider.dart';
import '../models/user.dart';
import '../widgets/scanner_widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../widgets/global_data_sync.dart';
import 'dart:async';

class PickingDetailScreen extends StatefulWidget {
  final int listId;
  const PickingDetailScreen({super.key, required this.listId});

  @override
  State<PickingDetailScreen> createState() => _PickingDetailScreenState();
}

class _PickingDetailScreenState extends State<PickingDetailScreen> {
  PickingList? _order;
  bool _isLoading = true;
  List<String> _selectedRecs = [];
  List<String> _selectedPsCodes = [];
  List<String> _selectedOprs = [];
  List<String> _selectedTrNos = [];
  List<String> _selectedGates = [];
  List<String> _selectedLines = [];
  List<String> _selectedZones = [];
  List<String> _selectedTyps = [];
  List<String> _selectedBoxes = [];
  bool _isScanning = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _confirmedSkus = {};
  PickingItem? _activeItem;
  int _lastScannedQty = 0;
  bool _isFocusMode = false;
  bool _pendingConfirmation = false;
  StreamSubscription? _refreshSub;

  @override
  void initState() {
    super.initState();
    _loadDetail();
    _refreshSub = GlobalDataSync.onRefresh.listen((category) {
      if (mounted && (category.contains('picking') || category == 'general')) {
        _loadDetail(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _refreshSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDetail({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    // Refresh user info if not admin to get latest assignments
    final auth = context.read<AuthProvider>();
    if (!auth.isAdmin) {
      await auth.refreshCurrentUser();
    }

    final detail = await ApiService().getPickingDetail(
      widget.listId,
      username: auth.currentUser?.username,
      recs: auth.currentUser?.assignedRecs,
      typs: auth.currentUser?.assignedTyps,
      ps: auth.currentUser?.assignedPs,
      oprs: auth.currentUser?.assignedOprs,
      tr: auth.currentUser?.assignedTr,
      gate: auth.currentUser?.assignedGate,
      line: auth.currentUser?.assignedLine,
      zone: auth.currentUser?.assignedZone,
      box: auth.currentUser?.assignedBox,
      isFiltered: !auth.isAdmin,
    );

    // Fetch users for assignment if admin
    if (auth.isAdmin) {
      await auth.fetchAllUsers();
    }

    setState(() {
      _order = detail;
      _isLoading = false;
    });
  }

  void _onScanSuccess(String code) async {
    if (_order == null) return;

    // Block scanning if there's a pending confirmation
    if (_pendingConfirmation) {
      _showMessage(
        'Vui lòng xác nhận hoặc hủy sản phẩm hiện tại trước khi quét tiếp!',
        isError: true,
      );
      setState(() => _isScanning = false);
      return;
    }

    // QR format: Part0:SKU:Part2:Qty:OPR:Part5
    // Example: 25112519024990:90103KPH 9001:90103KPH 9001  ZZZ:100:2M1712:
    List<String> parts = code.split(':');

    if (parts.length < 5) {
      _showMessage(
        'Mã QR không đúng định dạng (Thiếu thông tin)!',
        isError: true,
      );
      setState(() => _isScanning = false);
      return;
    }

    String scannedSku = parts[1].trim().replaceAll('-', '').replaceAll(' ', '');
    int scannedQty = int.tryParse(parts[3].trim()) ?? 0;
    String scannedOprFull = parts[4].trim();

    if (scannedQty <= 0) {
      _showMessage(
        'Mã QR có số lượng không hợp lệ ($scannedQty)!',
        isError: true,
      );
      setState(() => _isScanning = false);
      return;
    }

    // Attempt to match SKU and OPR across ALL items
    List<PickingItem> matches =
        _order!.items?.where((item) {
          bool skuMatch =
              item.sku.trim().replaceAll(' ', '').toUpperCase() ==
                  scannedSku.toUpperCase() ||
              (item.skuPlain ?? '').trim().replaceAll(' ', '').toUpperCase() ==
                  scannedSku.toUpperCase();
          if (!skuMatch) return false;

          if (item.rec_opr != null && item.rec_opr!.isNotEmpty) {
            String dbOpr = item.rec_opr!.trim().toUpperCase();
            String scanOpr = scannedOprFull.toUpperCase();
            return scanOpr.startsWith(dbOpr) ||
                dbOpr.startsWith(
                  scanOpr.substring(0, scanOpr.length > 2 ? 2 : scanOpr.length),
                );
          }
          return true;
        }).toList() ??
        [];

    if (matches.isEmpty) {
      _showMessage(
        'Không tìm thấy SKU $scannedSku với OPR tương ứng!',
        isError: true,
      );
      setState(() => _isScanning = false);
      return;
    }

    final user = context.read<AuthProvider>().currentUser;
    matches = matches
        .where((item) => user?.isAllowedToPick(item) ?? true)
        .toList();

    if (matches.isEmpty) {
      _showMessage('Bạn không có quyền soạn mã hàng này!', isError: true);
      setState(() => _isScanning = false);
      return;
    }

    // Prioritize items that are NOT yet full
    PickingItem? targetItem;
    try {
      targetItem = matches.firstWhere(
        (i) => i.quantityPicked < i.quantityRequired,
      );
    } catch (_) {
      // All potential matches are already full
      _showMessage('Mã hàng $scannedSku này đã soạn xong!', isError: true);
      setState(() => _isScanning = false);
      return;
    }

    // Validation: Do not allow picking if it exceeds requirement
    if (targetItem.quantityPicked + scannedQty > targetItem.quantityRequired) {
      int remaining = targetItem.quantityRequired - targetItem.quantityPicked;
      _showMessage(
        'Lỗi: Mã QR có $scannedQty PCS, nhưng chỉ còn cần $remaining PCS. Không thể soạn vượt mức!',
        isError: true,
      );
      setState(() => _isScanning = false);
      return;
    }

    // Fetch image and packaging standard if not present
    if (targetItem.imageUrl == null ||
        targetItem.packagingStandard == null ||
        targetItem.description == null ||
        targetItem.imageUrl2 == null) {
      // Try fetching with the item's SKU first
      var product = await ApiService().getProductBySku(targetItem.sku);

      // If that fails and the SKU has different formatting (e.g. spaces), try variants
      if (product == null) {
        // If target SKU has spaces, try removing them
        if (targetItem.sku.contains(' ')) {
          product = await ApiService().getProductBySku(
            targetItem.sku.replaceAll(' ', ''),
          );
        }
        // If still null, try the scanned SKU which we already stripped
        if (product == null &&
            scannedSku != targetItem.sku.replaceAll(' ', '')) {
          product = await ApiService().getProductBySku(scannedSku);
        }
      }

      if (product != null) {
        if (targetItem.imageUrl == null && product.imageUrl != null) {
          targetItem.imageUrl = product.imageUrl;
        }
        if (targetItem.imageUrl2 == null && product.imageUrl2 != null) {
          targetItem.imageUrl2 = product.imageUrl2;
        }
        targetItem.packagingStandard ??= product.packagingStandard;
        targetItem.description ??= product.description;
      }
    }

    // If already confirmed for this SKU, auto-confirm without showing button
    if (_confirmedSkus.contains(targetItem.sku)) {
      _confirmScan(targetItem, scannedQty);
      return;
    }

    setState(() {
      _activeItem = targetItem;
      _lastScannedQty = scannedQty;
      _isFocusMode = true;
      _isScanning = false;
      _pendingConfirmation = !_confirmedSkus.contains(
        targetItem!.sku,
      ); // Set pending if first time
    });
  }

  void _showScanConfirmationDialog(PickingItem item, int scannedQty) {
    showDialog(
      context: context,
      barrierDismissible: false, // User must interact
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.blue),
            const SizedBox(width: 10),
            const Text(
              'Xác nhận phụ tùng',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.imageUrl != null || item.imageUrl2 != null)
              Container(
                height: 120,
                margin: const EdgeInsets.only(bottom: 15),
                child: Row(
                  children: [
                    if (item.imageUrl != null)
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _buildNetworkImage(item.imageUrl!),
                        ),
                      ),
                    if (item.imageUrl != null && item.imageUrl2 != null)
                      const SizedBox(width: 8),
                    if (item.imageUrl2 != null)
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _buildNetworkImage(item.imageUrl2!),
                        ),
                      ),
                  ],
                ),
              ),
            const Text(
              'Kiểm tra thông tin chi tiết:',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 15),
            Text(
              'Mã SKU:',
              style: TextStyle(color: Colors.grey[600], fontSize: 11),
            ),
            Text(
              item.sku,

              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tên SP:',
              style: TextStyle(color: Colors.grey[600], fontSize: 11),
            ),
            Text(
              item.productName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            if (item.box != null && item.box!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'BOX:',
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),
              Text(
                item.box!,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF00796B),
                ),
              ),
            ],
            if (item.gate != null && item.gate!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'GATE:',
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),
              Text(
                item.gate!,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.blue,
                ),
              ),
            ],
            if (item.description != null && item.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Mô tả:',
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),
              Text(
                item.description!,
                style: const TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child:
                      Container(), // Empty for layout consistency if needed, or remove if not
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Số lượng soạn',
                        style: TextStyle(fontSize: 10, color: Colors.blue),
                      ),
                      Text(
                        '$scannedQty',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 30),
            if (item.zone != null || item.line != null)
              Row(
                children: [
                  const Icon(Icons.location_on, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'Vị trí: ${item.zone ?? ''} ${item.line ?? ''}',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.bar_chart, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'Tiến độ: ',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                Text(
                  '${item.quantityPicked} + $scannedQty / ${item.quantityRequired}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[800],
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _isScanning = false);
            },
            child: Text(
              'HỦY',
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              _confirmScan(item, scannedQty);
            },
            child: const Text(
              'XÁC NHẬN',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmScan(PickingItem targetItem, int scannedQty) async {
    // 1. Optimistic Update
    setState(() {
      targetItem.quantityPicked += scannedQty;
      _isScanning = false;
      _confirmedSkus.add(targetItem.sku);
      _pendingConfirmation = false;
    });

    // 2. Server Update
    await context.read<PickingProvider>().updateItemQuantity(
      targetItem,
      scannedQty,
      _order!.orderNumber,
    );

    _showMessage(
      'Đã soạn $scannedQty cho ${targetItem.sku}. (${targetItem.quantityPicked}/${targetItem.quantityRequired})',
    );

    // 3. Force Data Refresh to ensure consistency
    if (mounted) {
      _loadDetail(silent: true);
    }
  }

  void _showManualEntryDialog() {
    if (_pendingConfirmation) {
      _showMessage(
        'Vui lòng xác nhận hoặc hủy sản phẩm hiện tại trước!',
        isError: true,
      );
      return;
    }

    if (_order == null || _order!.items == null || _order!.items!.isEmpty) {
      _showMessage('Không có sản phẩm trong đơn hàng!', isError: true);
      return;
    }

    final TextEditingController skuController = TextEditingController();
    final TextEditingController qtyController = TextEditingController();
    List<PickingItem> suggestions = [];
    PickingItem? selectedItem;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.edit, color: Colors.orange),
                SizedBox(width: 10),
                Text(
                  'Nhập mã thủ công',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.9,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Nhập mã SKU:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: skuController,
                      decoration: InputDecoration(
                        hintText: 'Ví dụ: 90103KPH',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          if (value.isEmpty) {
                            suggestions = [];
                            selectedItem = null;
                          } else {
                            final user = context
                                .read<AuthProvider>()
                                .currentUser;
                            suggestions = _order!.items!
                                .where(
                                  (item) =>
                                      (item.sku.toUpperCase().contains(
                                            value.toUpperCase(),
                                          ) ||
                                          (item.skuPlain
                                                  ?.toUpperCase()
                                                  .contains(
                                                    value.toUpperCase(),
                                                  ) ??
                                              false) ||
                                          (item.rec_opr?.toUpperCase().contains(
                                                value.toUpperCase(),
                                              ) ??
                                              false)) &&
                                      (user?.isAllowedToPick(item) ?? true),
                                )
                                .take(5)
                                .toList();
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (suggestions.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: suggestions.length,
                          itemBuilder: (context, index) {
                            final item = suggestions[index];
                            return ListTile(
                              dense: true,
                              title: Text(
                                item.sku,

                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                '${item.productName}\n${item.rec_opr != null ? "OPR: ${item.rec_opr}" : ""}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Text(
                                '${item.quantityPicked}/${item.quantityRequired}',
                              ),
                              onTap: () {
                                setDialogState(() {
                                  selectedItem = item;
                                  skuController.text = item.sku;
                                  suggestions = [];
                                });
                              },
                            );
                          },
                        ),
                      ),
                    if (selectedItem != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Đã chọn:',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              selectedItem!.productName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (selectedItem!.rec_opr != null)
                              Text(
                                'OPR: ${selectedItem!.rec_opr}',
                                style: const TextStyle(fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Số lượng:',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: qtyController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'Nhập số lượng',
                          prefixIcon: const Icon(Icons.numbers),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text('HỦY', style: TextStyle(color: Colors.grey[600])),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  if (selectedItem == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Vui lòng chọn sản phẩm từ danh sách gợi ý!',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  final qty = int.tryParse(qtyController.text);
                  if (qty == null || qty <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Vui lòng nhập số lượng hợp lệ!'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  Navigator.pop(dialogContext);
                  _processManualEntry(selectedItem!, qty);
                },
                child: const Text(
                  'XÁC NHẬN',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _processManualEntry(PickingItem item, int qty) async {
    // Validate quantity
    if (item.quantityPicked + qty > item.quantityRequired) {
      int remaining = item.quantityRequired - item.quantityPicked;
      _showMessage(
        'Lỗi: Nhập $qty PCS, nhưng chỉ còn cần $remaining PCS!',
        isError: true,
      );
      return;
    }

    // Fetch image and packaging standard if not present
    if (item.imageUrl == null || item.packagingStandard == null) {
      final product = await ApiService().getProductBySku(item.sku);
      if (product != null) {
        if (item.imageUrl == null && product.imageUrl != null) {
          item.imageUrl = product.imageUrl;
        }
        item.packagingStandard ??= product.packagingStandard;
      }
    }

    // If already confirmed for this SKU, auto-confirm
    if (_confirmedSkus.contains(item.sku)) {
      _confirmScan(item, qty);
      return;
    }

    setState(() {
      _activeItem = item;
      _lastScannedQty = qty;
      _isFocusMode = true;
      _pendingConfirmation = true;
    });
  }

  Future<void> _exportToExcel() async {
    if (_order == null || _order!.items == null) return;

    try {
      var xlsp = excel.Excel.createExcel();
      excel.Sheet sheetObject = xlsp['Sheet1'];

      // Header style
      excel.CellStyle headerStyle = excel.CellStyle(
        bold: true,
        fontColorHex: excel.ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: excel.HorizontalAlign.Center,
        backgroundColorHex: excel.ExcelColor.fromHexString('#1565C0'),
      );

      // Headers
      List<String> headers = [
        'STT',
        'SKU',
        'Tên sản phẩm',
        'Số lượng yêu cầu',
        'Số lượng đã soạn',
        'Gate',
        'Line',
        'Zone',
        'REC HH',
        'TR.NO',
        'TYP',
        'BOX',
        'CODE',
        'RECOPR',
      ];

      for (var i = 0; i < headers.length; i++) {
        var cell = sheetObject.cell(
          excel.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
        );
        cell.value = excel.TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      // Final items to export (current filtered items)
      final itemsToExport = _filteredItems;

      // Data rows
      for (var i = 0; i < itemsToExport.length; i++) {
        final item = itemsToExport[i];
        final rowIndex = i + 1;

        sheetObject
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: 0,
                rowIndex: rowIndex,
              ),
            )
            .value = excel.IntCellValue(
          i + 1,
        );
        sheetObject
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: 1,
                rowIndex: rowIndex,
              ),
            )
            .value = excel.TextCellValue(
          item.sku,
        );

        sheetObject
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: 2,
                rowIndex: rowIndex,
              ),
            )
            .value = excel.TextCellValue(
          item.productName,
        );
        sheetObject
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: 3,
                rowIndex: rowIndex,
              ),
            )
            .value = excel.IntCellValue(
          item.quantityRequired,
        );
        sheetObject
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: 4,
                rowIndex: rowIndex,
              ),
            )
            .value = excel.IntCellValue(
          item.quantityPicked,
        );
        sheetObject
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: 5,
                rowIndex: rowIndex,
              ),
            )
            .value = excel.TextCellValue(
          item.gate ?? '',
        );
        sheetObject
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: 6,
                rowIndex: rowIndex,
              ),
            )
            .value = excel.TextCellValue(
          item.line ?? '',
        );
        sheetObject
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: 7,
                rowIndex: rowIndex,
              ),
            )
            .value = excel.TextCellValue(
          item.zone ?? '',
        );
        sheetObject
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: 8,
                rowIndex: rowIndex,
              ),
            )
            .value = excel.TextCellValue(
          item.rec_hh ?? '',
        );
        sheetObject
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: 9,
                rowIndex: rowIndex,
              ),
            )
            .value = excel.TextCellValue(
          item.tr_no ?? '',
        );
        sheetObject
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: 10,
                rowIndex: rowIndex,
              ),
            )
            .value = excel.TextCellValue(
          item.odr_typ ?? '',
        );
        sheetObject
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: 11,
                rowIndex: rowIndex,
              ),
            )
            .value = excel.TextCellValue(
          item.box ?? '',
        );
        sheetObject
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: 12,
                rowIndex: rowIndex,
              ),
            )
            .value = excel.TextCellValue(
          item.ps_cd ?? '',
        );
        sheetObject
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: 13,
                rowIndex: rowIndex,
              ),
            )
            .value = excel.TextCellValue(
          item.rec_opr ?? '',
        );
      }

      // Save file
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Chọn nơi lưu file Excel',
        fileName: 'Soan_hang_${_order!.orderNumber}.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (outputFile != null) {
        if (!outputFile.toLowerCase().endsWith('.xlsx')) {
          outputFile += '.xlsx';
        }

        var fileBytes = xlsp.save();
        if (fileBytes != null) {
          final file = File(outputFile);
          await file.create(recursive: true);
          await file.writeAsBytes(fileBytes);
          _showMessage('Đã xuất file thành công: $outputFile');
        }
      }
    } catch (e) {
      print('Export error: $e');
      _showMessage('Lỗi khi xuất file Excel: $e', isError: true);
    }
  }

  void _showMessage(String msg, {bool isError = false}) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        Future.delayed(const Duration(milliseconds: 2000), () {
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        });

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.check_circle_outline,
                  color: isError ? Colors.red : Colors.green,
                  size: 60,
                ),
                const SizedBox(height: 20),
                Text(
                  msg,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isError ? Colors.red[700] : Colors.green[700],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<PickingItem> get _filteredItems {
    if (_order == null || _order!.items == null) return [];
    final user = context.read<AuthProvider>().currentUser;
    return _order!.items!.where((item) {
      if (user != null && !user.isAllowedToPick(item)) return false;

      final matchRec =
          _selectedRecs.isEmpty || _selectedRecs.contains(item.rec_hh ?? '');
      final matchTr =
          _selectedTrNos.isEmpty || _selectedTrNos.contains(item.tr_no ?? '');
      final matchGate =
          _selectedGates.isEmpty || _selectedGates.contains(item.gate ?? '');
      final matchLine =
          _selectedLines.isEmpty || _selectedLines.contains(item.line ?? '');
      final matchZone =
          _selectedZones.isEmpty || _selectedZones.contains(item.zone ?? '');
      final matchTyp =
          _selectedTyps.isEmpty || _selectedTyps.contains(item.odr_typ ?? '');

      final query = _searchQuery.toLowerCase();
      final matchSearch =
          query.isEmpty ||
          item.productName.toLowerCase().contains(query) ||
          item.sku.toLowerCase().contains(query);

      return matchRec &&
          matchTr &&
          matchGate &&
          matchLine &&
          matchZone &&
          matchTyp &&
          matchSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    WakelockPlus.enable(); // Keep screen on during picking detail work
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_order == null)
      return const Scaffold(
        body: Center(child: Text('Không tìm thấy đơn hàng')),
      );

    bool allDone =
        _order!.items?.every((i) => i.quantityPicked >= i.quantityRequired) ??
        false;
    final filtered = _filteredItems;

    if (_isFocusMode && _activeItem != null) {
      return _buildActiveFocusView();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Soạn hàng: ${_order!.orderNumber}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _exportToExcel,
            tooltip: 'Xuất Excel',
          ),
          if (_isFocusMode)
            IconButton(
              icon: const Icon(Icons.list_alt),
              onPressed: () => setState(() => _isFocusMode = false),
              tooltip: 'Xem danh sách',
            ),
        ],
      ),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildSummaryHeader()),
              SliverToBoxAdapter(child: _buildSearchBar()),
              SliverToBoxAdapter(child: _buildFilterBar()),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final item = filtered[index];
                    return Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: _buildItemCard(item, index + 1),
                    );
                  }, childCount: filtered.length),
                ),
              ),
              if (allDone)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: () async {
                          await context.read<PickingProvider>().completePicking(
                            _order!.id!,
                            _order!.orderNumber,
                          );
                          Navigator.pop(context);
                        },
                        child: const Text(
                          'HOÀN THÀNH',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
          if (_isScanning) _buildScannerOverlay(),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'manual_list',
            onPressed: _showManualEntryDialog,
            backgroundColor: Colors.orange,
            tooltip: 'Nhập thủ công',
            child: const Icon(Icons.keyboard, color: Colors.white),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'scan_list',
            onPressed: () {
              if (_pendingConfirmation) {
                _showMessage(
                  'Vui lòng xác nhận hoặc hủy sản phẩm hiện tại!',
                  isError: true,
                );
                return;
              }
              setState(() => _isScanning = true);
            },
            backgroundColor: Colors.blue,
            tooltip: 'Quét mã',
            child: const Icon(Icons.qr_code_scanner, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFocusView() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết soạn hàng'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _isFocusMode = false),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_activeItem!.imageUrl != null ||
                      _activeItem!.imageUrl2 != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          if (_activeItem!.imageUrl != null)
                            SizedBox(
                              width:
                                  (MediaQuery.of(context).size.width -
                                              40 -
                                              12) /
                                          2 >
                                      100
                                  ? (MediaQuery.of(context).size.width -
                                            40 -
                                            12) /
                                        2
                                  : MediaQuery.of(context).size.width - 40,
                              height: 120,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: Colors.grey[100],
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: _buildNetworkImage(
                                    _activeItem!.imageUrl!,
                                  ),
                                ),
                              ),
                            ),
                          if (_activeItem!.imageUrl2 != null)
                            SizedBox(
                              width:
                                  (_activeItem!.imageUrl != null &&
                                      (MediaQuery.of(context).size.width -
                                                  40 -
                                                  12) /
                                              2 >
                                          100)
                                  ? (MediaQuery.of(context).size.width -
                                            40 -
                                            12) /
                                        2
                                  : MediaQuery.of(context).size.width - 40,
                              height: 120,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: Colors.grey[100],
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: _buildNetworkImage(
                                    _activeItem!.imageUrl2!,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mã SKU:',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              _activeItem!.sku,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 22,
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tên sản phẩm:',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              _activeItem!.productName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          const SizedBox(height: 18),
                          if (_activeItem!.line != null &&
                              _activeItem!.line!.isNotEmpty) ...[
                            _buildTag(
                              'Line: ${_activeItem!.line}',
                              Colors.orange,
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (_activeItem!.zone != null &&
                              _activeItem!.zone!.isNotEmpty)
                            _buildTag(
                              'Zone: ${_activeItem!.zone}',
                              Colors.purple,
                            ),
                        ],
                      ),
                    ],
                  ),

                  if (_activeItem!.packagingStandard != null &&
                      _activeItem!.packagingStandard!.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          'Tiêu chuẩn đóng gói:',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Text(
                            _activeItem!.packagingStandard!,
                            style: const TextStyle(fontSize: 14, height: 1.5),
                          ),
                        ),
                      ],
                    ),

                  if (_activeItem!.description != null &&
                      _activeItem!.description!.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          'Mô tả sản phẩm:',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue[50]?.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.blue[100]!.withOpacity(0.5),
                            ),
                          ),
                          child: Text(
                            _activeItem!.description!,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),

                  const Divider(height: 16),

                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.blue[100]!),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.blue.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Text(
                                    'Tiến độ: ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: Colors.blue,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    '${_activeItem!.quantityPicked}/${_activeItem!.quantityRequired}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_activeItem!.box != null &&
                                _activeItem!.box!.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF00796B,
                                  ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF00796B,
                                    ).withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  'BOX: ${_activeItem!.box}',
                                  style: const TextStyle(
                                    color: Color(0xFF00796B),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: _activeItem!.quantityRequired > 0
                                ? _activeItem!.quantityPicked /
                                      _activeItem!.quantityRequired
                                : 0,
                            minHeight: 12,
                            backgroundColor: Colors.white,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Quick quantity input section (for already confirmed SKUs)
                  if (_confirmedSkus.contains(_activeItem!.sku) &&
                      _activeItem!.quantityPicked <
                          _activeItem!.quantityRequired)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Nhập nhanh số lượng:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    hintText: 'Số lượng',
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                  onSubmitted: (value) {
                                    final qty = int.tryParse(value);
                                    if (qty != null && qty > 0) {
                                      _quickAddQuantity(qty);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildQuickQtyButton(10),
                              _buildQuickQtyButton(50),
                              _buildQuickQtyButton(100),
                              _buildQuickQtyButton(200),
                            ],
                          ),
                        ],
                      ),
                    ),

                  if (_confirmedSkus.contains(_activeItem!.sku) &&
                      _activeItem!.quantityPicked <
                          _activeItem!.quantityRequired)
                    const SizedBox(height: 20),

                  // Only show confirm button if this SKU hasn't been confirmed yet
                  if (!_confirmedSkus.contains(_activeItem!.sku) &&
                      _activeItem!.quantityPicked <
                          _activeItem!.quantityRequired)
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 60,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 4,
                            ),
                            onPressed: () =>
                                _confirmScan(_activeItem!, _lastScannedQty),
                            child: Text(
                              'XÁC NHẬN SOẠN $_lastScannedQty PCS',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.red),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                _pendingConfirmation = false;
                                _isFocusMode = false;
                                _activeItem = null;
                              });
                            },
                            child: const Text(
                              'HỦY',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  else if (_activeItem!.quantityPicked >=
                      _activeItem!.quantityRequired)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle, color: Colors.green),
                          SizedBox(width: 8),
                          Text(
                            'ĐÃ SOẠN ĐỦ SỐ LƯỢNG',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_isScanning) _buildScannerOverlay(),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'manual_focus',
            onPressed: _showManualEntryDialog,
            backgroundColor: Colors.orange,
            tooltip: 'Nhập thủ công',
            child: const Icon(Icons.keyboard, color: Colors.white),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'scan_focus',
            onPressed: () {
              if (_pendingConfirmation) {
                _showMessage(
                  'Vui lòng xác nhận hoặc hủy sản phẩm hiện tại!',
                  isError: true,
                );
                return;
              }
              setState(() => _isScanning = true);
            },
            backgroundColor: Colors.blue,
            tooltip: 'Quét mã',
            child: const Icon(Icons.qr_code_scanner, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader() {
    final totalLines = _order?.items?.length ?? 0;
    final totalRequired =
        _order?.items?.fold<int>(
          0,
          (sum, item) => sum + item.quantityRequired,
        ) ??
        0;
    final totalPicked =
        _order?.items?.fold<int>(0, (sum, item) => sum + item.quantityPicked) ??
        0;

    return Container(
      width: double.infinity,
      color: Theme.of(context).primaryColor.withOpacity(0.05),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Khách hàng: ${_order!.customer}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    children: [
                      Icon(
                        _order!.status == 'completed'
                            ? Icons.check_circle
                            : Icons.pending,
                        size: 14,
                        color: _order!.status == 'completed'
                            ? Colors.green
                            : Colors.orange,
                      ),
                      Text(
                        'Trạng thái: ${_order!.status == 'completed' ? 'Hoàn thành' : 'Đang thực hiện'}',
                        style: TextStyle(
                          fontSize: 13,
                          color: _order!.status == 'completed'
                              ? Colors.green
                              : Colors.orange[800],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.2)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$totalPicked / $totalRequired',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$totalLines mã hàng (dòng)',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    if (_order == null || _order!.items == null) return const SizedBox.shrink();

    final recs =
        _order!.items!
            .map((i) => i.rec_hh ?? '')
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final trnos =
        _order!.items!
            .map((i) => i.tr_no ?? '')
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final gates =
        _order!.items!
            .map((i) => i.gate ?? '')
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final lines =
        _order!.items!
            .map((i) => i.line ?? '')
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final zones =
        _order!.items!
            .map((i) => i.zone ?? '')
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final typs =
        _order!.items!
            .map((i) => i.odr_typ ?? '')
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final boxesItems =
        _order!.items!
            .map((i) => i.box ?? '')
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    bool hasAnyFilter =
        _selectedRecs.isNotEmpty ||
        _selectedTrNos.isNotEmpty ||
        _selectedGates.isNotEmpty ||
        _selectedLines.isNotEmpty ||
        _selectedZones.isNotEmpty ||
        _selectedTyps.isNotEmpty ||
        _selectedBoxes.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Icon(Icons.filter_alt_outlined, size: 18, color: Colors.blue),
              Text(
                'Bộ lọc nâng cao (Chọn nhiều)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterButton(
                  'REC HH',
                  _selectedRecs,
                  recs,
                  (newVal) => setState(() => _selectedRecs = newVal),
                ),
                const SizedBox(width: 8),
                _buildFilterButton(
                  'TR.NO',
                  _selectedTrNos,
                  trnos,
                  (newVal) => setState(() => _selectedTrNos = newVal),
                ),
                const SizedBox(width: 8),
                _buildFilterButton(
                  'GATE',
                  _selectedGates,
                  gates,
                  (newVal) => setState(() => _selectedGates = newVal),
                ),
                const SizedBox(width: 8),
                _buildFilterButton(
                  'LINE',
                  _selectedLines,
                  lines,
                  (newVal) => setState(() => _selectedLines = newVal),
                ),
                const SizedBox(width: 8),
                _buildFilterButton(
                  'ZONE',
                  _selectedZones,
                  zones,
                  (newVal) => setState(() => _selectedZones = newVal),
                ),
                const SizedBox(width: 8),
                _buildFilterButton(
                  'TYP',
                  _selectedTyps,
                  typs,
                  (newVal) => setState(() => _selectedTyps = newVal),
                ),
                const SizedBox(width: 8),
                _buildFilterButton(
                  'BOX',
                  _selectedBoxes,
                  boxesItems,
                  (newVal) => setState(() => _selectedBoxes = newVal),
                ),
                if (context.read<AuthProvider>().isAdmin && hasAnyFilter) ...[
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _showAssignDialog,
                    icon: const Icon(Icons.assignment_ind, size: 16),
                    label: const Text(
                      'GÁN NHÂN VIÊN',
                      style: TextStyle(fontSize: 11),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
                if (hasAnyFilter) ...[
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => setState(() {
                      _selectedRecs = [];
                      _selectedTrNos = [];
                      _selectedGates = [];
                      _selectedLines = [];
                      _selectedZones = [];
                      _selectedTyps = [];
                      _selectedBoxes = [];
                    }),
                    child: const Text(
                      'Xóa tất cả',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAssignDialog() {
    final auth = context.read<AuthProvider>();
    User? selectedUser;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.assignment_ind, color: Colors.blue),
              SizedBox(width: 10),
              Text('Chỉ định người soạn'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nội dung phân công dựa trên bộ lọc hiện tại:',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              if (_selectedRecs.isNotEmpty)
                Text(
                  '• REC: ${_selectedRecs.join(', ')}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              if (_selectedTrNos.isNotEmpty)
                Text(
                  '• TR.NO: ${_selectedTrNos.join(', ')}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              if (_selectedGates.isNotEmpty)
                Text(
                  '• GATE: ${_selectedGates.join(', ')}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              if (_selectedLines.isNotEmpty)
                Text(
                  '• LINE: ${_selectedLines.join(', ')}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              if (_selectedZones.isNotEmpty)
                Text(
                  '• ZONE: ${_selectedZones.join(', ')}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              if (_selectedTyps.isNotEmpty)
                Text(
                  '• TYP: ${_selectedTyps.join(', ')}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              if (_selectedBoxes.isNotEmpty)
                Text(
                  '• BOX: ${_selectedBoxes.join(', ')}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              const SizedBox(height: 20),
              const Text(
                'Chọn nhân viên:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<User>(
                initialValue: selectedUser,
                hint: const Text('Chọn nhân viên...'),
                items: auth.allUsers
                    .where((u) => u.role != UserRole.admin)
                    .map(
                      (u) =>
                          DropdownMenuItem(value: u, child: Text(u.username)),
                    )
                    .toList(),
                onChanged: (val) => setModalState(() => selectedUser = val),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Lưu ý: Thao tác này sẽ cập nhật (ghi đè) phân công hiện tại của nhân viên được chọn.',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.orange,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('HỦY'),
            ),
            ElevatedButton(
              onPressed: selectedUser == null
                  ? null
                  : () async {
                      // Performing assignment at item level for this order.

                      // Assuming we want to set exactly what is filtered.
                      // If a filter is EMPTY, we keep the user's existing assignment for that type or clear it?
                      // The user said "chỉ hiển thị những thông tin admin chỉ định" - implying we set these fields.

                      final success = await ApiService().assignPickingItems(
                        listId: _order!.id!,
                        username: selectedUser!.username,
                        recs: _selectedRecs.isNotEmpty ? _selectedRecs : null,
                        trs: _selectedTrNos.isNotEmpty ? _selectedTrNos : null,
                        gates: _selectedGates.isNotEmpty
                            ? _selectedGates
                            : null,
                        lines: _selectedLines.isNotEmpty
                            ? _selectedLines
                            : null,
                        zones: _selectedZones.isNotEmpty
                            ? _selectedZones
                            : null,
                        typs: _selectedTyps.isNotEmpty ? _selectedTyps : null,
                        boxes: _selectedBoxes.isNotEmpty
                            ? _selectedBoxes
                            : null,
                        pscds: _selectedPsCodes.isNotEmpty
                            ? _selectedPsCodes
                            : null,
                        oprs: _selectedOprs.isNotEmpty ? _selectedOprs : null,
                      );

                      if (success) {
                        Navigator.pop(ctx);
                        _showMessage(
                          'Đã phân công thành công cho ${selectedUser!.username}',
                        );
                        _loadDetail();
                      } else {
                        _showMessage(
                          'Lỗi khi phân công nhân viên!',
                          isError: true,
                        );
                      }
                    },
              child: const Text('XÁC NHẬN GÁN'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterButton(
    String label,
    List<String> selected,
    List<String> options,
    Function(List<String>) onUpdate,
  ) {
    bool hasSelection = selected.isNotEmpty;
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        backgroundColor: hasSelection ? Colors.blue[50] : Colors.transparent,
        side: BorderSide(color: hasSelection ? Colors.blue : Colors.grey[300]!),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      ),
      onPressed: () => _showMultiSelect(label, options, selected, onUpdate),
      icon: Icon(
        Icons.keyboard_arrow_down,
        size: 16,
        color: hasSelection ? Colors.blue : Colors.grey[600],
      ),
      label: Text(
        hasSelection ? '$label (${selected.length})' : label,
        style: TextStyle(
          fontSize: 12,
          color: hasSelection ? Colors.blue : Colors.grey[700],
          fontWeight: hasSelection ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  void _showMultiSelect(
    String title,
    List<String> options,
    List<String> currentSelected,
    Function(List<String>) onUpdate,
  ) {
    List<String> tempSelected = List.from(currentSelected);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Lọc theo $title',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setModalState(() => tempSelected = []);
                        },
                        child: const Text('Xóa chọn'),
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final opt = options[index];
                        final isSelected = tempSelected.contains(opt);
                        return CheckboxListTile(
                          title: Text(opt),
                          value: isSelected,
                          onChanged: (val) {
                            setModalState(() {
                              if (val == true) {
                                tempSelected.add(opt);
                              } else {
                                tempSelected.remove(opt);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        onUpdate(tempSelected);
                        Navigator.pop(context);
                      },
                      child: const Text('ÁP DỤNG'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildItemCard(PickingItem item, int stt) {
    bool isDone = item.quantityPicked >= item.quantityRequired;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDone ? Colors.green[50] : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          setState(() {
            _activeItem = item;
            _isFocusMode = true;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stt < 10 ? '0$stt' : stt.toString(),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[400],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.sku,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            letterSpacing: 0.5,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.productName,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${item.quantityPicked} / ${item.quantityRequired}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDone ? Colors.green : Colors.blue,
                        ),
                      ),
                      const Text('Số lượng', style: TextStyle(fontSize: 10)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (item.gate != null && item.gate!.isNotEmpty)
                    _buildTag('Gate: ${item.gate}', Colors.blue),
                  if (item.line != null && item.line!.isNotEmpty)
                    _buildTag('Line: ${item.line}', Colors.orange),
                  if (item.zone != null && item.zone!.isNotEmpty)
                    _buildTag('Zone: ${item.zone}', Colors.purple),
                ],
              ),
              if ((item.rec_hh?.isNotEmpty ?? false) ||
                  (item.tr_no?.isNotEmpty ?? false) ||
                  (item.odr_typ?.isNotEmpty ?? false) ||
                  (item.box?.isNotEmpty ?? false) ||
                  (item.ps_cd?.isNotEmpty ?? false) ||
                  (item.rec_opr?.isNotEmpty ?? false))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      if (item.rec_hh?.isNotEmpty ?? false)
                        _buildInfoText(
                          'REC HH',
                          item.rec_hh!,
                          const Color(0xFF7B1FA2),
                        ),
                      if (item.tr_no?.isNotEmpty ?? false)
                        _buildInfoText(
                          'TR.NO',
                          item.tr_no!,
                          const Color(0xFF0288D1),
                        ),
                      if (item.odr_typ?.isNotEmpty ?? false)
                        _buildInfoText(
                          'TYP',
                          item.odr_typ!,
                          const Color(0xFFE65100),
                        ),
                      if (item.box?.isNotEmpty ?? false)
                        _buildInfoText(
                          'BOX',
                          item.box!,
                          const Color(0xFF00796B),
                        ),
                      if (item.ps_cd?.isNotEmpty ?? false)
                        _buildInfoText(
                          'CODE',
                          item.ps_cd!,
                          const Color(0xFF388E3C),
                        ),
                      if (item.rec_opr?.isNotEmpty ?? false)
                        _buildInfoText(
                          'RECOPR',
                          item.rec_opr!,
                          const Color(0xFFC62828),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildInfoText(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: color.withOpacity(0.8),
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            MobileScanner(
              controller: MobileScannerController(
                facing: CameraFacing.back,
                torchEnabled: false,
              ),
              onDetect: (capture) {
                final List<Barcode> barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  if (barcode.rawValue != null) {
                    _onScanSuccess(barcode.rawValue!);
                    break;
                  }
                }
              },
            ),
            // Semi-transparent overlay with a cutout
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withOpacity(0.7),
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 280,
                      height: 280,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Rounded corner indicators for the scan window
            Center(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.blue.withOpacity(0.5),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: CustomPaint(
                  painter: ScannerCornerPainter(color: Colors.blue),
                ),
              ),
            ),
            // Header
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => setState(() => _isScanning = false),
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        'QUÉT MÃ QR',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: 48,
                    ), // Transparent spacer to keep title centered
                  ],
                ),
              ),
            ),
            // Footer Instructions
            Positioned(
              bottom: 80,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        Icon(
                          Icons.qr_code_scanner,
                          color: Colors.blue,
                          size: 20,
                        ),
                        Text(
                          'Đưa mã QR vào khung quét',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Scanning Animation (Laser Line)
            const ScanningAnimation(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      color: Theme.of(context).primaryColor.withOpacity(0.05),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Tìm theo tên hoặc SKU...',
          hintStyle: TextStyle(fontSize: 14, color: Colors.grey[500]),
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 0,
            horizontal: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.blue.withOpacity(0.2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.blue.withOpacity(0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.blue),
          ),
        ),
        onChanged: (val) => setState(() => _searchQuery = val),
      ),
    );
  }

  Widget _buildQuickQtyButton(int qty) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: () => _quickAddQuantity(qty),
      child: Text('+$qty', style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  void _quickAddQuantity(int qty) async {
    if (_activeItem == null) return;

    // Validate quantity
    if (_activeItem!.quantityPicked + qty > _activeItem!.quantityRequired) {
      int remaining =
          _activeItem!.quantityRequired - _activeItem!.quantityPicked;
      _showMessage(
        'Lỗi: Nhập $qty PCS, nhưng chỉ còn cần $remaining PCS!',
        isError: true,
      );
      return;
    }

    // Directly add without confirmation (since SKU already confirmed)
    setState(() {
      _activeItem!.quantityPicked += qty;
    });

    // Update on server
    await context.read<PickingProvider>().updateItemQuantity(
      _activeItem!,
      qty,
      _order!.orderNumber,
    );

    // Auto-refresh UI
    setState(() {});
  }

  Widget _buildNetworkImage(String path) {
    return Image.network(
      path.startsWith('http') ? path : '${ApiService().uploadUrl}$path',
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        color: Colors.grey[200],
        child: const Center(
          child: Icon(Icons.image_not_supported, color: Colors.grey),
        ),
      ),
    );
  }
}

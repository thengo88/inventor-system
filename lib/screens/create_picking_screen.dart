import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../providers/picking_provider.dart';
import '../providers/product_provider.dart';

class CreatePickingScreen extends StatefulWidget {
  final String? location;
  final String? type;

  const CreatePickingScreen({super.key, this.location, this.type});

  @override
  State<CreatePickingScreen> createState() => _CreatePickingScreenState();
}

class _CreatePickingScreenState extends State<CreatePickingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _orderController = TextEditingController();
  final _customerController = TextEditingController();

  dynamic _excelFileData; // File (Mobile) or List<int> (Web)
  String? _fileName;
  final List<Map<String, dynamic>> _manualItems = [];
  bool _isExcelMode = true;
  bool _isSaving = false;
  List<String> _availableSheets = [];
  String? _selectedSheet;
  bool _isLoadingSheets = false;
  List<String> _availableDates = [];
  String? _selectedDate;
  bool _isLoadingDates = false;

  // Header Mapping
  List<String> _availableHeaders = [];
  bool _isLoadingHeaders = false;
  final Map<String, String> _columnMapping = {};
  bool _showColumnMapping = false;

  @override
  void initState() {
    super.initState();
    if (widget.location != null) {
      _customerController.text = widget.location!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.location != null && widget.type != null
        ? '${widget.location} - ${widget.type}'
        : 'Tạo đơn soạn hàng';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tạo đơn soạn hàng', style: TextStyle(fontSize: 16)),
            if (widget.location != null && widget.type != null)
              Text(
                '${widget.location} - ${widget.type}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTextField(
                _orderController,
                'Mã đơn hàng (Tự động nếu để trống)',
                Icons.numbers,
                isRequired: false,
              ),

              const SizedBox(height: 16),
              _buildTextField(_customerController, 'Khách hàng', Icons.person),
              const SizedBox(height: 32),

              Row(
                children: [
                  Expanded(
                    child: _TabButton(
                      title: 'Nhập Excel',
                      isActive: _isExcelMode,
                      onTap: () => setState(() => _isExcelMode = true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TabButton(
                      title: 'Nhập thủ công',
                      isActive: !_isExcelMode,
                      onTap: () => setState(() => _isExcelMode = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              if (_isExcelMode) _buildExcelPicker() else _buildManualEntry(),

              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _submit,
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'TẠO ĐƠN HÀNG',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isRequired = true,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      validator: (v) =>
          (isRequired && v!.isEmpty) ? 'Vui lòng nhập $label' : null,
    );
  }

  Widget _buildExcelPicker() {
    return Column(
      children: [
        GestureDetector(
          onTap: _pickFile,
          child: Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blue[100]!, width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.file_upload_outlined,
                  size: 40,
                  color: Colors.blue[700],
                ),
                const SizedBox(height: 8),
                Text(
                  _fileName == null ? 'Chọn file Excel (.xlsx)' : _fileName!,
                  style: TextStyle(color: Colors.blue[700]),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'File Excel cần có các cột: PT_NO, PART_NAME, REC_HH, PS_CD, ODR_TYP, REC_OPR',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        if (_isLoadingSheets) ...[
          const SizedBox(height: 24),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 8),
          const Text(
            'Đang tải danh sách sheet...',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ] else if (_availableSheets.isNotEmpty) ...[
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            value: _selectedSheet,
            decoration: InputDecoration(
              labelText: 'Chọn Sheet',
              prefixIcon: const Icon(Icons.table_chart),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            items: _availableSheets
                .map(
                  (sheet) => DropdownMenuItem(value: sheet, child: Text(sheet)),
                )
                .toList(),
            onChanged: (value) {
              setState(() => _selectedSheet = value);
              _loadDates();
              _loadHeaders();
            },
          ),
          if (_isLoadingDates) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 4),
            const Text(
              'Đang quét ngày trong sheet...',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ] else if (_availableDates.isNotEmpty) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedDate,
              decoration: InputDecoration(
                labelText: 'Chọn Cột Ngày (Từ tiêu đề Excel)',
                prefixIcon: const Icon(Icons.calendar_today),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Tất cả ngày'),
                ),
                ..._availableDates.map(
                  (date) => DropdownMenuItem(value: date, child: Text(date)),
                ),
              ],
              onChanged: (value) => setState(() => _selectedDate = value),
            ),
            const SizedBox(height: 8),
            const Text(
              'Chọn ngày cụ thể để lọc đơn hàng từ timing list.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.green,
                fontStyle: FontStyle.italic,
              ),
            ),
          ] else if (_excelFileData != null && !_isLoadingDates) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.grey),
                  SizedBox(width: 8),
                  Text(
                    'Không thể nhận diện các tiêu đề cột dữ liệu trong sheet này.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Chọn sheet chứa dữ liệu cần nhập. Nếu không chọn, sheet đầu tiên sẽ được sử dụng.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.blue,
              fontStyle: FontStyle.italic,
            ),
          ),
        ] else if (_excelFileData != null && !_isLoadingSheets) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Không thể đọc danh sách sheet. File sẽ sử dụng sheet đầu tiên.',
                    style: TextStyle(fontSize: 12, color: Colors.orange[900]),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        _buildColumnMappingSection(),
      ],
    );
  }

  Future<void> _loadDates() async {
    if (_excelFileData == null || _selectedSheet == null) return;

    setState(() {
      _isLoadingDates = true;
      _availableDates = [];
      _selectedDate = null;
    });

    try {
      final dates = await context
          .read<PickingProvider>()
          .apiService
          .getExcelDates(_excelFileData, selectedSheet: _selectedSheet);

      if (mounted) {
        setState(() {
          _isLoadingDates = false;
          if (dates != null && dates.isNotEmpty) {
            _availableDates = dates;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingDates = false);
    }
  }

  Widget _buildManualEntry() {
    return Column(
      children: [
        ..._manualItems.asMap().entries.map((entry) {
          int idx = entry.key;
          var item = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Sản phẩm'),
                      initialValue: item['sku'],
                      items: context.read<ProductProvider>().products.map((p) {
                        return DropdownMenuItem(
                          value: p.sku,
                          child: Text(p.name, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          item['sku'] = val;
                          item['name'] = context
                              .read<ProductProvider>()
                              .products
                              .firstWhere((p) => p.sku == val)
                              .name;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      decoration: const InputDecoration(labelText: 'SL'),
                      keyboardType: TextInputType.number,
                      initialValue: item['quantity']?.toString() ?? '1',
                      onChanged: (val) =>
                          item['quantity'] = int.tryParse(val) ?? 1,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => setState(() => _manualItems.removeAt(idx)),
                  ),
                ],
              ),
            ),
          );
        }),
        TextButton.icon(
          onPressed: () => setState(
            () => _manualItems.add({'sku': null, 'name': null, 'quantity': 1}),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Thêm sản phẩm'),
        ),
      ],
    );
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: kIsWeb, // Important for Web
    );

    if (result != null) {
      if (kIsWeb) {
        setState(() {
          _excelFileData = result.files.single.bytes;
          _fileName = result.files.single.name;
          _isLoadingSheets = true;
          _availableSheets = [];
          _selectedSheet = null;
        });
      } else {
        setState(() {
          _excelFileData = File(result.files.single.path!);
          _fileName = result.files.single.name;
          _isLoadingSheets = true;
          _availableSheets = [];
          _selectedSheet = null;
        });
      }

      try {
        final sheets = await context
            .read<PickingProvider>()
            .apiService
            .getExcelSheets(_excelFileData);

        if (mounted) {
          setState(() {
            _isLoadingSheets = false;
            if (sheets != null && sheets.isNotEmpty) {
              _availableSheets = sheets;
              _selectedSheet = sheets.first;
              _loadDates();
              _loadHeaders();
            }
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoadingSheets = false;
          });
          _showMessage('Không thể đọc danh sách sheet từ file Excel');
        }
      }
    }
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    if (_isExcelMode) {
      if (_excelFileData == null) {
        _showMessage('Vui lòng chọn file Excel');
        setState(() => _isSaving = false);
        return;
      }

      final result = await context.read<PickingProvider>().importFromExcel(
        _orderController.text,
        _customerController.text,
        _excelFileData,
        selectedSheet: _selectedSheet,
        selectedDate: _selectedDate,
        columnMapping: _columnMapping.isEmpty ? null : _columnMapping,
      );

      setState(() => _isSaving = false);
      if (result != null && mounted) {
        // Show Enhanced Summary Dialog
        final List orders = result['orders'] ?? [];
        final int orderCount = result['orderCount'] ?? 1;

        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 28),
                const SizedBox(width: 12),
                Text(
                  orderCount > 1
                      ? 'Đã nhập $orderCount đơn hàng'
                      : 'Thành công',
                ),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (orderCount > 1) ...[
                    const Text(
                      'Danh sách đơn hàng đã nhận diện:',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: orders.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final o = orders[index];
                          return ListTile(
                            dense: true,
                            title: Text(
                              'Trip: ${o['orderNumber']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            trailing: Text(
                              '${o['count']} mã - ${o['qty']} SP',
                              style: const TextStyle(color: Colors.blue),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ] else ...[
                    Text(
                      'Mã đơn: ${result['orderNumber']}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Tổng số mã (dòng):'),
                            Text(
                              '${result['importedCount']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Tổng số lượng SP:'),
                            Text(
                              '${result['totalQuantity']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('XÁC NHẬN'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.pop(context);
      } else if (result == null) {
        _showMessage('Có lỗi xảy ra khi nhập Excel, vui lòng thử lại');
      }
    } else {
      if (_manualItems.isEmpty || _manualItems.any((i) => i['sku'] == null)) {
        _showMessage('Vui lòng nhập đầy đủ sản phẩm');
        setState(() => _isSaving = false);
        return;
      }

      final success = await context.read<PickingProvider>().createPicking(
        _orderController.text,
        _customerController.text,
        _manualItems,
      );

      setState(() => _isSaving = false);
      if (success && mounted) {
        Navigator.pop(context);
      } else if (!success) {
        _showMessage('Có lỗi xảy ra, vui lòng thử lại');
      }
    }
  }

  Widget _buildColumnMappingSection() {
    if (_isLoadingHeaders) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // Only show if we have headers
    if (_availableHeaders.isEmpty) return const SizedBox.shrink();

    return ExpansionTile(
      title: const Text(
        'Cấu hình cột (Tùy chọn)',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
      subtitle: const Text(
        'Ánh xạ cột Excel vào dữ liệu hệ thống (Mặc định tự động)',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      ),
      initiallyExpanded: _showColumnMapping,
      onExpansionChanged: (val) => setState(() => _showColumnMapping = val),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              _buildMappingRow('sku', 'Mã SKU / Part No (*)', isRequired: true),
              _buildMappingRow('qty', 'Số lượng (*)'),
              _buildMappingRow('tripname', 'Lot No / Order / Trip'),
              _buildMappingRow('rechh', 'REC / Bin / Vị trí'),
              _buildMappingRow('trno', 'TR No / Trip No'),
              _buildMappingRow('odrtyp', 'Order Type / Loại đơn'),
              _buildMappingRow('gate', 'Gate / Cổng'),
              _buildMappingRow('line', 'Line / Chuyền'),
              _buildMappingRow('zone', 'Zone / Khu vực'),
              _buildMappingRow('recopr', 'Operator / Người làm'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMappingRow(String key, String label, {bool isRequired = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isRequired ? FontWeight.bold : FontWeight.normal,
                color: isRequired ? Colors.black87 : Colors.grey[700],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              value: _columnMapping[key],
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(),
              ),
              hint: const Text(
                'Tự động (Auto)',
                style: TextStyle(fontSize: 12),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text(
                    'Tự động (Auto)',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ..._availableHeaders.map(
                  (h) => DropdownMenuItem(
                    value: h,
                    child: Text(h, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (val) {
                setState(() {
                  if (val == null) {
                    _columnMapping.remove(key);
                  } else {
                    _columnMapping[key] = val;
                  }
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadHeaders() async {
    if (_excelFileData == null) return;
    // Don't require sheet selected if only one sheet exists, but typically API handles default.
    // _selectedSheet might be null if auto-selected first sheet in background.

    setState(() {
      _isLoadingHeaders = true;
      _availableHeaders = [];
      _columnMapping.clear();
    });

    try {
      final headers = await context.read<PickingProvider>().getExcelHeaders(
        _excelFileData!,
        selectedSheet: _selectedSheet,
      );

      if (mounted) {
        setState(() {
          _isLoadingHeaders = false;
          if (headers != null) {
            _availableHeaders = headers;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingHeaders = false);
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _TabButton extends StatelessWidget {
  final String title;
  final bool isActive;
  final VoidCallback onTap;

  const _TabButton({
    required this.title,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? Theme.of(context).primaryColor : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

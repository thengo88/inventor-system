import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';

class AuditHistoryTab extends StatefulWidget {
  const AuditHistoryTab({super.key});

  @override
  State<AuditHistoryTab> createState() => _AuditHistoryTabState();
}

class _AuditHistoryTabState extends State<AuditHistoryTab> {
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  List<dynamic> _historyData = [];
  List<dynamic> _filteredData = [];
  final TextEditingController _auditorFilterController =
      TextEditingController();
  final TextEditingController _skuFilterController = TextEditingController();

  // Controllers for synchronized horizontal scrolling
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _headerHorizontalController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _horizontalController.addListener(() {
      if (_headerHorizontalController.hasClients) {
        _headerHorizontalController.jumpTo(_horizontalController.offset);
      }
    });
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _headerHorizontalController.dispose();
    _auditorFilterController.dispose();
    _skuFilterController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final data = await _apiService.getAuditHistory();
      setState(() {
        _historyData = data;
        _applyFilters();
      });
    } catch (e) {
      debugPrint('Error loading history: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    final auditorQuery = _auditorFilterController.text.toLowerCase();
    final skuQuery = _skuFilterController.text.toLowerCase();

    setState(() {
      _filteredData = _historyData.where((item) {
        final auditor = (item['auditor'] ?? '').toString().toLowerCase();
        final sku = (item['sku'] ?? '').toString().toLowerCase();
        final skuPlain = (item['sku_plain'] ?? '').toString().toLowerCase();
        return auditor.contains(auditorQuery) &&
            (sku.contains(skuQuery) || skuPlain.contains(skuQuery));
      }).toList();
    });
  }

  Future<void> _deleteSingle(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: const Text('Bạn có chắc muốn xóa bản ghi này?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _apiService.deleteAuditRecord(id);
      if (success) _loadHistory();
    }
  }

  void _showEditDialog(Map<String, dynamic> item) {
    // Controllers
    final standardCtrl = TextEditingController(
      text: item['packagingStandard']?.toString() ?? '0',
    );
    final horCtrl = TextEditingController(
      text: item['horRows']?.toString() ?? '0',
    );
    final verCtrl = TextEditingController(
      text: item['verRows']?.toString() ?? '0',
    );
    final evenCtrl = TextEditingController(
      text: item['evenRows']?.toString() ?? '0',
    );
    final oddCtrl = TextEditingController(
      text: item['oddRows']?.toString() ?? '0',
    );
    final bagCtrl = TextEditingController(
      text: item['individualBags']?.toString() ?? '0',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sửa số lượng: ${item['sku']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildNumberField('Quy cách (Standard)', standardCtrl),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildNumberField('Hàng ngang', horCtrl)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildNumberField('Hàng dọc', verCtrl)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildNumberField('SL Full (Even)', evenCtrl),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _buildNumberField('Hàng lẻ (Odd)', oddCtrl)),
                ],
              ),
              const SizedBox(height: 8),
              _buildNumberField('Túi lẻ (Bags)', bagCtrl),
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
              int packagingStandard = int.tryParse(standardCtrl.text) ?? 0;
              int horRows = int.tryParse(horCtrl.text) ?? 0;
              int verRows = int.tryParse(verCtrl.text) ?? 0;
              int evenRows = int.tryParse(evenCtrl.text) ?? 0;
              int oddRows = int.tryParse(oddCtrl.text) ?? 0;
              int individualBags = int.tryParse(bagCtrl.text) ?? 0;

              // Calculate total immediately just for sanity,
              // but Server/Backend usually recalculates total based on these inputs
              // OR we send these and backend updates total.
              // Assuming API expects these fields.

              final updateData = {
                'packagingStandard': packagingStandard,
                'horRows': horRows,
                'verRows': verRows,
                'evenRows': evenRows,
                'oddRows': oddRows,
                'individualBags': individualBags,
                // Total is derivative, but if we want to be safe we can send it or let backend handle.
                // Based on previous code, total = (packagingStandard * evenRows * horRows * verRows) + oddRows + individualBags ??
                // Actually the formula varies. Let's send the raw inputs.
              };

              final success = await _apiService.updateAuditRecord(
                item['id'],
                updateData,
              );
              if (success) {
                Navigator.pop(ctx);
                _loadHistory();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cập nhật thất bại')),
                );
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberField(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildFilters(),
        Expanded(
          child: _isLoading && _historyData.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _filteredData.isEmpty
              ? _buildEmptyState()
              : _buildVirtualizedTable(),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[100],
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _auditorFilterController,
                  decoration: const InputDecoration(
                    labelText: 'Người kiểm kê',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => _applyFilters(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _skuFilterController,
                  decoration: const InputDecoration(
                    labelText: 'Mã vật tư',
                    prefixIcon: Icon(Icons.qr_code),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => _applyFilters(),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _loadHistory,
                icon: const Icon(Icons.refresh),
                label: const Text('Làm mới'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'Chưa có lịch sử kiểm kê',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildVirtualizedTable() {
    return Column(
      children: [
        // FIXED HEADER
        SingleChildScrollView(
          controller: _headerHorizontalController,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Container(
            color: Colors.grey[200],
            width: 1500, // Total width increased for Warehouse column
            child: Row(
              children: [
                _cell('ID', width: 60, isHeader: true),
                _cell('Mã số', width: 150, isHeader: true),
                _cell('Kho', width: 100, isHeader: true),
                _cell('Tiêu chuẩn', width: 100, isHeader: true),
                _cell('Ngang', width: 80, isHeader: true),
                _cell('Dọc', width: 80, isHeader: true),
                _cell('SL Full', width: 80, isHeader: true),
                _cell('Hàng lẻ', width: 80, isHeader: true),
                _cell('Túi lẻ', width: 80, isHeader: true),
                _cell('Tổng SL', width: 100, isHeader: true),
                _cell('Người kiểm', width: 150, isHeader: true),
                _cell('Thời gian', width: 160, isHeader: true),
                _cell('Thao tác', width: 150, isHeader: true),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        // VIRTUALIZED BODY
        Expanded(
          child: SingleChildScrollView(
            controller: _horizontalController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 1500,
              child: ListView.separated(
                itemCount: _filteredData.length,
                separatorBuilder: (ctx, i) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _filteredData[index];
                  final time = item['timestamp'] != null
                      ? DateFormat(
                          'dd/MM/yyyy HH:mm',
                        ).format(DateTime.parse(item['timestamp']))
                      : '-';

                  return Container(
                    height: 52,
                    color: index % 2 == 0
                        ? Colors.white
                        : Colors.grey[50]?.withOpacity(0.5),
                    child: Row(
                      children: [
                        _cell(item['id'], width: 60),
                        _cell(
                          item['sku'] ?? '',
                          width: 150,
                          color: Colors.blue,
                          weight: FontWeight.bold,
                        ),
                        _cell(item['warehouse'] ?? '-', width: 100),
                        _cell(item['packagingStandard'] ?? '0', width: 100),
                        _cell(item['horRows'] ?? '0', width: 80),
                        _cell(item['verRows'] ?? '0', width: 80),
                        _cell(item['evenRows'] ?? '0', width: 80),
                        _cell(item['oddRows'] ?? '0', width: 80),
                        _cell(item['individualBags'] ?? '0', width: 80),
                        _cell(
                          item['totalResult'] ?? '0',
                          width: 100,
                          weight: FontWeight.bold,
                        ),
                        _cell(item['auditor'] ?? '', width: 150),
                        _cell(time, width: 160),
                        _buildActions(item, 150),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _cell(
    dynamic text, {
    required double width,
    bool isHeader = false,
    Color? color,
    FontWeight? weight,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Text(
        text.toString(),
        style: TextStyle(
          fontWeight: isHeader ? FontWeight.bold : weight,
          color: isHeader ? Colors.black87 : color,
          fontSize: 13,
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildActions(Map<String, dynamic> item, double width) {
    return Container(
      width: width,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
            onPressed: () => _showEditDialog(item),
            constraints: const BoxConstraints(),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red, size: 20),
            onPressed: () => _deleteSingle(item['id']),
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

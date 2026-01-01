import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/picking_provider.dart';
import '../../providers/auth_provider.dart';

class PickingHistoryScreen extends StatefulWidget {
  const PickingHistoryScreen({super.key});

  @override
  State<PickingHistoryScreen> createState() => _PickingHistoryScreenState();
}

class _PickingHistoryScreenState extends State<PickingHistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;
  String? _selectedUser;
  List<String> _allUsernames = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final history = await context.read<PickingProvider>().getPickingHistory();
    final auth = context.read<AuthProvider>();

    // Extract unique usernames for filter (only for admin)
    final usernames =
        history
            .map((h) => h['username']?.toString() ?? 'Unknown')
            .toSet()
            .toList()
          ..sort();

    setState(() {
      _history = history;
      _allUsernames = usernames;
      _isLoading = false;

      // If not admin, restrict to self
      if (!auth.isAdmin && auth.currentUser != null) {
        _selectedUser = auth.currentUser!.username;
      }
    });
  }

  List<Map<String, dynamic>> get _filteredHistory {
    final auth = context.read<AuthProvider>();

    // If not admin, ALWAYS filter by self
    if (!auth.isAdmin && auth.currentUser != null) {
      return _history
          .where((h) => h['username'] == auth.currentUser!.username)
          .toList();
    }

    if (_selectedUser == null || _selectedUser == 'Tất cả') {
      return _history;
    }
    return _history.where((h) => h['username'] == _selectedUser).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredData = _filteredHistory;
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Lịch sử soạn hàng'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistory,
            tooltip: 'Làm mới',
          ),
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              onPressed: _confirmClearHistory,
              tooltip: 'Xóa sạch lịch sử',
            ),
        ],
      ),
      body: Column(
        children: [
          // Filter & Stats Bar
          if (auth.isAdmin)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        width: 250,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedUser ?? 'Tất cả',
                            isExpanded: true,
                            icon: const Icon(
                              Icons.person_search,
                              color: Colors.blue,
                            ),
                            hint: const Text('Lọc theo nhân viên'),
                            items: ['Tất cả', ..._allUsernames].map((
                              String value,
                            ) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(
                                  value,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              );
                            }).toList(),
                            onChanged: (newValue) {
                              setState(() {
                                _selectedUser = newValue;
                              });
                            },
                          ),
                        ),
                      ),
                      Container(
                        width: 100,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blue[100]!),
                        ),
                        child: Column(
                          children: [
                            Text(
                              filteredData.length.toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Colors.blue,
                              ),
                            ),
                            const Text(
                              'Bản ghi',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredData.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history_toggle_off,
                          size: 80,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _selectedUser == null || _selectedUser == 'Tất cả'
                              ? 'Chưa có bất kỳ lịch sử soạn hàng nào.'
                              : 'Không tìm thấy lịch sử cho: $_selectedUser',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 16,
                          ),
                        ),
                        if (_selectedUser != null && _selectedUser != 'Tất cả')
                          TextButton(
                            onPressed: () =>
                                setState(() => _selectedUser = 'Tất cả'),
                            child: const Text('Hiện tất cả'),
                          ),
                      ],
                    ),
                  )
                : Theme(
                    data: Theme.of(context).copyWith(
                      cardTheme: CardThemeData(
                        elevation: 0,
                        margin: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(0),
                        ),
                      ),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Card(
                          child: DataTable(
                            headingRowHeight: 50,
                            dataRowHeight: 60,
                            horizontalMargin: 20,
                            columnSpacing: 20,
                            headingRowColor: WidgetStateProperty.all(
                              Colors.grey[50],
                            ),
                            columns: const [
                              DataColumn(
                                label: Text(
                                  'NHÂN VIÊN',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'ĐƠN HÀNG',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'MÃ SKU',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'SL',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'THỜI GIAN',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'TR.NO',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'REC',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'TYP',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'PS',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'OPR',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'GATE',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'LINE',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'ZONE',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'BOX',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'PHỤ TÙNG',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ],
                            rows: filteredData.map((h) {
                              final timestamp =
                                  DateTime.tryParse(h['timestamp'] ?? '') ??
                                  DateTime.now();
                              return DataRow(
                                cells: [
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue[600]!.withOpacity(
                                          0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        h['username'] ?? '?',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue[800],
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      h['orderNumber'] ?? '',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      h['sku'] ?? '',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Center(
                                      child: Text(
                                        h['quantityPicked']?.toString() ?? '0',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          DateFormat(
                                            'dd/MM/yyyy',
                                          ).format(timestamp),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        Text(
                                          DateFormat(
                                            'HH:mm:ss',
                                          ).format(timestamp),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      h['tr_no'] ?? '',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      h['rec_hh'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.purple,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      h['odr_typ'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.orange,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      h['ps_cd'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      h['rec_opr'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      h['gate'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.teal,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      h['line'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.deepOrange,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      h['zone'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.blueGrey,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      h['box'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.brown,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    SizedBox(
                                      width: 150,
                                      child: Text(
                                        h['productName'] ?? '',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[800],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _confirmClearHistory() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa sạch?'),
        content: const Text('Lịch sử soạn hàng sẽ bị xóa vĩnh viễn.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () async {
              final success = await context
                  .read<PickingProvider>()
                  .clearHistory();
              if (success) {
                _loadHistory();
              }
              Navigator.pop(ctx);
            },
            child: const Text(
              'Xóa tất cả',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}

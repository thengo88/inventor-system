import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/picking_provider.dart';
import '../providers/auth_provider.dart';
import '../models/picking_list.dart';
import 'picking_detail_screen.dart';
import 'create_picking_screen.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../widgets/global_data_sync.dart';
import 'dart:async';

class PickingScreen extends StatefulWidget {
  const PickingScreen({super.key});

  @override
  @override
  State<PickingScreen> createState() => _PickingScreenState();
}

class _PickingScreenState extends State<PickingScreen>
    with WidgetsBindingObserver {
  final TextEditingController _recFilterController = TextEditingController();
  final TextEditingController _psFilterController = TextEditingController();
  final TextEditingController _oprFilterController = TextEditingController();
  bool _isFilterExpanded = false;
  StreamSubscription? _refreshSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() async {
      final auth = context.read<AuthProvider>();
      if (!auth.isAdmin) {
        await auth.refreshCurrentUser();
      }
      if (mounted) {
        context.read<PickingProvider>().fetchPickingLists();
      }
    });
    if (context.read<AuthProvider>().isAdmin) {
      context.read<AuthProvider>().fetchAllUsers();
    }

    _refreshSub = GlobalDataSync.onRefresh.listen((category) {
      // Refresh if category is picking, or general
      if (category == 'picking' || category == 'general') {
        _applyFilters(); // Re-fetch with current filters
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshSub?.cancel();
    _recFilterController.dispose();
    _psFilterController.dispose();
    _oprFilterController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh when app comes to foreground
      _applyFilters();
    }
  }

  void _applyFilters() {
    context.read<PickingProvider>().fetchPickingLists(
      recs: _recFilterController.text,
      ps: _psFilterController.text,
      oprs: _oprFilterController.text,
    );
  }

  void _clearFilters() {
    _recFilterController.clear();
    _psFilterController.clear();
    _oprFilterController.clear();
    context.read<PickingProvider>().fetchPickingLists();
  }

  @override
  Widget build(BuildContext context) {
    WakelockPlus.enable(); // Ensure screen stays on
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Danh sách soạn hàng'),
        actions: [
          if (auth.isAdmin)
            IconButton(
              icon: Icon(
                _isFilterExpanded
                    ? Icons.filter_alt
                    : Icons.filter_alt_outlined,
              ),
              onPressed: () =>
                  setState(() => _isFilterExpanded = !_isFilterExpanded),
              tooltip: 'Bộ lọc nâng cao (Admin)',
            ),
        ],
      ),
      floatingActionButton: auth.isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _showOrderTypeDialog(),
              label: const Text('Thêm đơn hàng'),
              icon: const Icon(Icons.add),
            )
          : null,
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            if (auth.isAdmin && _isFilterExpanded) _buildAdminFilterBar(auth),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Theme.of(context).primaryColor,
                ),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey[600],
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                tabs: const [
                  Tab(text: 'HVN Phú Thọ'),
                  Tab(text: 'HVN Ninh Bình'),
                ],
              ),
            ),
            Expanded(
              child: Consumer<PickingProvider>(
                builder: (context, provider, child) {
                  if (provider.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return TabBarView(
                    key: ValueKey(provider.pickingLists.length),
                    children: [
                      _buildOrderList(provider, 'HVN Phú Thọ'),
                      _buildOrderList(provider, 'HVN Ninh Bình'),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderList(PickingProvider provider, String customerName) {
    final filteredLists = provider.pickingLists.where((l) {
      final c = l.customer.trim().toLowerCase();
      final target = customerName.trim().toLowerCase();

      // Exact match
      if (c == target) return true;

      // Alias matches for older records
      if (target.contains('phú thọ')) {
        return c == 'hvn' ||
            c == 'vp' ||
            c.contains('phu tho') ||
            c.contains('phú thọ');
      }
      if (target.contains('ninh bình')) {
        return c == 'nb' || c.contains('ninh binh') || c.contains('ninh bình');
      }

      return false;
    }).toList();

    if (filteredLists.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'Chưa có đơn hàng cho $customerName',
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredLists.length,
      itemBuilder: (context, index) {
        final list = filteredLists[index];
        return _buildPickingCard(list, index + 1);
      },
    );
  }

  Widget _buildAdminFilterBar(AuthProvider auth) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _recFilterController,
                  decoration: const InputDecoration(
                    labelText: 'REC',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _psFilterController,
                  decoration: const InputDecoration(
                    labelText: 'PS',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _oprFilterController,
                  decoration: const InputDecoration(
                    labelText: 'OPR',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('Xóa lọc'),
                style: TextButton.styleFrom(foregroundColor: Colors.grey),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _applyFilters,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Xem trước'),
              ),
              if (_recFilterController.text.isNotEmpty ||
                  _psFilterController.text.isNotEmpty ||
                  _oprFilterController.text.isNotEmpty) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _showAssignDialog(auth),
                  icon: const Icon(Icons.assignment_ind, size: 18),
                  label: const Text('GÁN NHÂN VIÊN'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showAssignDialog(AuthProvider auth) {
    User? selectedUser;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Giao phó công việc'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Bạn đang gán các tiêu chí sau cho nhân viên:',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              if (_recFilterController.text.isNotEmpty)
                Text(
                  '• REC: ${_recFilterController.text}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              if (_psFilterController.text.isNotEmpty)
                Text(
                  '• PS: ${_psFilterController.text}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              if (_oprFilterController.text.isNotEmpty)
                Text(
                  '• OPR: ${_oprFilterController.text}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              const SizedBox(height: 20),
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
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Nhân viên',
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
                      await auth.editUser(
                        selectedUser!.id!,
                        selectedUser!.username,
                        null,
                        selectedUser!.role,
                        recs: _recFilterController.text,
                        ps: _psFilterController.text,
                        oprs: _oprFilterController.text,
                      );
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã gán công việc cho ${selectedUser!.username}',
                          ),
                        ),
                      );
                    },
              child: const Text('XÁC NHẬN GÁN'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickingCard(PickingList list, int stt) {
    bool isCompleted = list.status == 'completed';
    double progress = 0;
    if (list.totalQtyRequired != null && list.totalQtyRequired! > 0) {
      progress = (list.totalQtyPicked ?? 0) / list.totalQtyRequired!;
    }

    // Ensure progress is between 0 and 1
    progress = progress.clamp(0.0, 1.0);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PickingDetailScreen(listId: list.id!),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isCompleted
                              ? Colors.green[50]
                              : Colors.blue[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            stt.toString(),
                            style: TextStyle(
                              color: isCompleted
                                  ? Colors.green[700]
                                  : Colors.blue[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Đơn: ${list.orderNumber}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'KH: ${list.customer}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStatusBadge(list.status),
                      if (context.read<AuthProvider>().isAdmin)
                        Padding(
                          padding: const EdgeInsets.only(left: 4.0),
                          child: IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.grey,
                              size: 20,
                            ),
                            onPressed: () => _confirmDelete(list),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 16,
                runSpacing: 8,
                children: [
                  _buildDetailItem(
                    Icons.inventory_2_outlined,
                    '${list.totalItems ?? 0} mã hàng',
                  ),
                  _buildDetailItem(
                    Icons.numbers_outlined,
                    '${list.totalQtyPicked ?? 0} / ${list.totalQtyRequired ?? 0} PCS',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.grey[100],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isCompleted ? Colors.green : Colors.blue,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    DateFormat('dd/MM/yyyy HH:mm').format(list.createdAt),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                  Text(
                    '${(progress * 100).toInt()}% Hoàn thành',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isCompleted ? Colors.green : Colors.blue[700],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    bool isCompleted = status == 'completed';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isCompleted ? Colors.green[50] : Colors.orange[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCompleted ? Colors.green[200]! : Colors.orange[200]!,
        ),
      ),
      child: Text(
        isCompleted ? 'Xong' : 'Chờ',
        style: TextStyle(
          color: isCompleted ? Colors.green[700] : Colors.orange[700],
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showOrderTypeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.add_business, color: Colors.blue),
            SizedBox(width: 10),
            Text('Chọn loại đơn hàng', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // HVN Phú Thọ
            _buildLocationCard('HVN Phú Thọ', Icons.factory, Colors.blue, () {
              Navigator.pop(ctx);
              _showTypeSelectionDialog('HVN Phú Thọ');
            }),
            const SizedBox(height: 12),
            // HVN Ninh Bình
            _buildLocationCard(
              'HVN Ninh Bình',
              Icons.factory_outlined,
              Colors.green,
              () {
                Navigator.pop(ctx);
                _showTypeSelectionDialog('HVN Ninh Bình');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard(
    String location,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3), width: 2),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                location,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 20),
          ],
        ),
      ),
    );
  }

  void _showTypeSelectionDialog(String location) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              location,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Chọn loại nhập liệu',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Theo Timinglist
            _buildTypeCard(
              'Theo Timinglist',
              Icons.schedule,
              Colors.purple,
              'Nhập đơn hàng theo danh sách thời gian',
              () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreatePickingScreen(
                      location: location,
                      type: 'Timinglist',
                    ),
                  ),
                ).then((_) {
                  // Refresh picking lists after returning
                  context.read<PickingProvider>().fetchPickingLists();
                });
              },
            ),
            const SizedBox(height: 12),
            // Theo VHL
            _buildTypeCard(
              'Theo VHL',
              Icons.local_shipping,
              Colors.orange,
              'Nhập đơn hàng theo Vehicle Loading',
              () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        CreatePickingScreen(location: location, type: 'VHL'),
                  ),
                ).then((_) {
                  // Refresh picking lists after returning
                  context.read<PickingProvider>().fetchPickingLists();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeCard(
    String title,
    IconData icon,
    Color color,
    String description,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3), width: 2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 18),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(PickingList list) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text(
          'Bạn có chắc chắn muốn xóa đơn hàng ${list.orderNumber}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('HỦY'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await context
                  .read<PickingProvider>()
                  .deletePicking(list.id!, list.orderNumber);
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã xóa đơn hàng')),
                );
              }
            },
            child: const Text('XÓA', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

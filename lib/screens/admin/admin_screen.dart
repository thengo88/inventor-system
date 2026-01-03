import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:inventor/providers/auth_provider.dart';
import 'package:inventor/providers/settings_provider.dart';
import 'user_management_screen.dart';
import 'audit_history_tab.dart';
import 'notifications_tab.dart';
import 'system_screen.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  @override
  Widget build(BuildContext context) {
    WakelockPlus.enable(); // Prevent sleep in admin screen
    final zoom = context.watch<SettingsProvider>().zoomLevel;
    return Scaffold(
      appBar: AppBar(title: const Text('Bảng Quản trị'), centerTitle: true),
      body: LayoutBuilder(
        builder: (context, constraints) {
          int crossAxisCount = constraints.maxWidth > 800 ? 3 : 2;
          double baseAspectRatio = constraints.maxWidth > 800 ? 1.5 : 1.0;
          double aspectRatio =
              baseAspectRatio / (zoom > 1.0 ? (1.0 + (zoom - 1.0) * 1.5) : 1.0);

          return GridView.count(
            padding: const EdgeInsets.all(20),
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 20,
            crossAxisSpacing: 20,
            childAspectRatio: aspectRatio,
            children: [
              _buildAdminMenu(
                context,
                'Nhân viên',
                Icons.people_outline,
                Colors.orange,
                () => _navigateTo(
                  context,
                  'Nhân viên',
                  const UserManagementScreen(),
                ),
              ),
              _buildAdminMenu(
                context,
                'Nhật ký',
                Icons.receipt_long_outlined,
                Colors.teal,
                () => _navigateTo(context, 'Nhật ký', const _LogsTab()),
              ),
              _buildAdminMenu(
                context,
                'Thông báo',
                Icons.notifications_active_outlined,
                Colors.red,
                () =>
                    _navigateTo(context, 'Thông báo', const NotificationsTab()),
              ),
              _buildAdminMenu(
                context,
                'Hệ thống',
                Icons.settings_suggest_outlined,
                Colors.indigo,
                () => _navigateTo(context, 'Cấu hình Hệ thống', const SystemScreen()),
              ),
            ],
          );
        },
      ),
    );
  }

  void _navigateTo(BuildContext context, String title, Widget tab) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: tab,
        ),
      ),
    );
  }

  Widget _buildAdminMenu(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogsTab extends StatefulWidget {
  const _LogsTab();

  @override
  State<_LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<_LogsTab> {
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().fetchLogs();
    });
  }

  void _confirmDelete(
    BuildContext context,
    String title,
    String content,
    VoidCallback onConfirm,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, child) {
        return Column(
          children: [
            // Toolbar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[100],
              child: Row(
                children: [
                  if (_selectedIds.isNotEmpty) ...[
                    Text(
                      'Đã chọn ${_selectedIds.length}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () => _confirmDelete(
                        context,
                        'Xóa đã chọn',
                        'Bạn có chắc muốn xóa ${_selectedIds.length} nhật ký đã chọn?',
                        () {
                          auth
                              .removeMultipleLogs(_selectedIds.toList())
                              .then(
                                (_) => setState(() => _selectedIds.clear()),
                              );
                        },
                      ),
                      icon: const Icon(Icons.delete, size: 16),
                      label: const Text('Xóa mục chọn'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => _confirmDelete(
                      context,
                      'Xóa tất cả',
                      'Bạn có chắc muốn xóa TOÀN BỘ nhật ký hệ thống?',
                      () => auth.clearLogs(),
                    ),
                    icon: const Icon(Icons.delete_forever, size: 16),
                    label: const Text('Xóa tất cả'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // List
            Expanded(
              child: auth.logs.isEmpty
                  ? const Center(child: Text('Chưa có nhật ký hoạt động'))
                  : ListView.separated(
                      itemCount: auth.logs.length,
                      separatorBuilder: (ctx, i) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final log = auth.logs[index];
                        final id = log.id;
                        if (id == null) return const SizedBox.shrink();

                        final isSelected = _selectedIds.contains(id);
                        return ListTile(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedIds.remove(id);
                              } else {
                                _selectedIds.add(id);
                              }
                            });
                          },
                          leading: Checkbox(
                            value: isSelected,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedIds.add(id);
                                } else {
                                  _selectedIds.remove(id);
                                }
                              });
                            },
                          ),
                          title: Text(
                            log.action,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${log.username} - ${log.details}\n${DateFormat('dd/MM HH:mm').format(log.timestamp)}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.grey,
                            ),
                            onPressed: () => _confirmDelete(
                              context,
                              'Xóa nhật ký',
                              'Xóa nhật ký này?',
                              () => auth.removeLog(id),
                            ),
                          ),
                          tileColor: isSelected
                              ? Colors.blue.withOpacity(0.05)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

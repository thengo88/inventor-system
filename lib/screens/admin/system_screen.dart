import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:inventor/providers/settings_provider.dart';
import 'package:inventor/providers/product_provider.dart';
import 'erp_data_tab.dart';
import 'audit_history_tab.dart';

class SystemScreen extends StatefulWidget {
  const SystemScreen({super.key});

  @override
  State<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends State<SystemScreen> {
  @override
  Widget build(BuildContext context) {
    final zoom = context.watch<SettingsProvider>().zoomLevel;
    return Scaffold(
      appBar: AppBar(title: const Text('Hệ thống Quản trị'), centerTitle: true),
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
              _buildSystemButton(
                context,
                'Dữ liệu ERP',
                Icons.cloud_download_outlined,
                Colors.indigo,
                () => _navigateTo(context, 'Dữ liệu ERP', const ErpDataTab()),
              ),
              _buildSystemButton(
                context,
                'Lịch sử KK',
                Icons.history,
                Colors.brown,
                () =>
                    _navigateTo(context, 'Lịch sử KK', const AuditHistoryTab()),
              ),
              _buildSystemButton(
                context,
                'Cấu hình',
                Icons.settings,
                Colors.blueGrey,
                () => _navigateTo(
                  context,
                  'Cấu hình Hệ thống',
                  const _SystemSettingsView(),
                ),
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

  Widget _buildSystemButton(
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

class _SystemSettingsView extends StatelessWidget {
  const _SystemSettingsView();

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.storage, color: Colors.blueGrey),
                        SizedBox(width: 10),
                        Text(
                          'Cấu hình Nguồn Dữ liệu',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Chọn nguồn dữ liệu tồn kho mặc định cho toàn hệ thống:',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    RadioListTile<String>(
                      title: const Text(
                        'Bảng dữ liệu ERP (Excel)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text('Lấy số lượng từ tệp Excel đồng bộ'),
                      value: 'erp',
                      groupValue: settings.stockSource,
                      onChanged: (val) => _updateStockSource(context, val),
                    ),
                    RadioListTile<String>(
                      title: const Text(
                        'Sản phẩm (ANC-WMS)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text('Lấy số lượng từ nhập tay/quét kho'),
                      value: 'anc-wms',
                      groupValue: settings.stockSource,
                      onChanged: (val) => _updateStockSource(context, val),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _updateStockSource(BuildContext context, String? val) async {
    if (val != null) {
      final settings = context.read<SettingsProvider>();
      final success = await settings.setStockSource(val);
      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Đã cập nhật nguồn dữ liệu: ${val == 'erp' ? 'ERP' : 'ANC-WMS'}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }
}

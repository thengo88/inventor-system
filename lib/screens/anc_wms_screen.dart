import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/product_provider.dart';
import 'admin/warehouse_layout_screen.dart';
import 'admin/anc_wms_data_tab.dart';
import 'scan_screen.dart';

class AncWmsScreen extends StatelessWidget {
  const AncWmsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final zoom = context.watch<SettingsProvider>().zoomLevel;
    return Scaffold(
      appBar: AppBar(title: const Text('ANC-WMS'), centerTitle: true),
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
              _buildMenuButton(
                context,
                'Nhập kho',
                Icons.qr_code_scanner,
                Colors.blue,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ScanScreen()),
                  );
                },
              ),
              _buildMenuButton(
                context,
                'Danh mục sản phẩm',
                Icons.map_outlined,
                Colors.orange,
                () {
                  final products = context.read<ProductProvider>().products;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          WarehouseLayoutScreen(allProducts: products),
                    ),
                  );
                },
              ),
              _buildMenuButton(
                context,
                'Danh sách tồn kho sản phẩm',
                Icons.table_chart_outlined,
                Colors.teal,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => Scaffold(
                        appBar: AppBar(
                          title: const Text('Danh sách tồn kho sản phẩm'),
                        ),
                        body: const AncWmsDataTab(),
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMenuButton(
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
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

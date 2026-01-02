import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/product.dart';
import '../../services/api_service.dart';
import '../../widgets/global_data_sync.dart';
import 'edit_product_screen.dart';
import 'warehouse_layout_screen.dart';

class ProductsTab extends StatefulWidget {
  const ProductsTab({super.key});

  @override
  State<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<ProductsTab> with WidgetsBindingObserver {
  String _searchQuery = "";
  StreamSubscription? _refreshSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProductProvider>().fetchProducts();
    });

    _refreshSub = GlobalDataSync.onRefresh.listen((category) {
      if (mounted &&
          (category.contains('product') ||
              category.contains('erp') ||
              category == 'general')) {
        context.read<ProductProvider>().fetchProducts();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<ProductProvider>().fetchProducts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProductProvider>(
      builder: (context, provider, child) {
        final allProducts = provider.products;
        final totalSkus = allProducts.length;
        final Map<String, int> customerStats = {};
        final Set<String> uniqueLocations = {};

        for (var p in allProducts) {
          customerStats[p.customer] = (customerStats[p.customer] ?? 0) + 1;
          if (p.layoutPosition.isNotEmpty) {
            uniqueLocations.add(p.layoutPosition);
          }
        }

        final filteredProducts = allProducts.where((p) {
          final query = _searchQuery.toLowerCase();
          return p.name.toLowerCase().contains(query) ||
              p.sku.toLowerCase().contains(query) ||
              (p.skuPlain ?? '').toLowerCase().contains(query) ||
              p.customer.toLowerCase().contains(query) ||
              p.layoutPosition.toLowerCase().contains(query);
        }).toList();

        return Scaffold(
          floatingActionButton: FloatingActionButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EditProductScreen()),
            ),
            backgroundColor: Colors.blue,
            child: const Icon(Icons.add, color: Colors.white),
          ),
          body: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  border: Border(
                    bottom: BorderSide(color: Colors.blue.withOpacity(0.1)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "TỔNG QUAN HÀNG HÓA",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.blue,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildSummaryCard(
                            "Tổng SKU",
                            totalSkus.toString(),
                            Icons.inventory_2,
                            Colors.blue,
                            onTap: () {},
                          ),
                          _buildSummaryCard(
                            "Vị trí kho",
                            uniqueLocations.length.toString(),
                            Icons.location_on,
                            Colors.orange,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => WarehouseLayoutScreen(
                                  allProducts: allProducts,
                                ),
                              ),
                            ),
                          ),
                          ...customerStats.entries.map(
                            (e) => _buildSummaryCard(
                              "Khách: ${e.key}",
                              e.value.toString(),
                              Icons.person,
                              Colors.teal,
                              onTap: () => _showFilteredProducts(
                                context,
                                "Sản phẩm: ${e.key}",
                                allProducts
                                    .where((p) => p.customer == e.key)
                                    .toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                child: TextField(
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: InputDecoration(
                    hintText: 'Tìm SKU, Tên, Khách hàng, Vị trí...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                  ),
                ),
              ),
              Expanded(
                child: filteredProducts.isEmpty
                    ? const Center(child: Text("Không tìm thấy sản phẩm"))
                    : ListView.builder(
                        itemCount: filteredProducts.length,
                        itemBuilder: (context, index) {
                          return _buildProductCard(
                            context,
                            filteredProducts[index],
                            index,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFilteredProducts(
    BuildContext context,
    String title,
    List<Product> products,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: products.length,
            itemBuilder: (context, index) {
              return _buildProductCard(context, products[index], index);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildProductCard(BuildContext context, Product p, int index) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 45,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue, Color(0xFF1565C0)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.tag, size: 14, color: Colors.white70),
                  Text(
                    "${index + 1}",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Hero(
                          tag: 'prod_${p.id}_$index',
                          child: Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: _buildProductThumbnail(p.imageUrl),
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      p.sku,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20,
                                        color: Colors.blue,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_note_rounded,
                                      color: Colors.blue,
                                      size: 28,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            EditProductScreen(product: p),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                p.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.teal.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.person,
                                      size: 14,
                                      color: Colors.teal,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "Khách: ${p.customer}",
                                      style: const TextStyle(
                                        color: Colors.teal,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Divider(height: 1),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoItem(
                            Icons.inventory_2_rounded,
                            "Quy cách",
                            p.packagingStandard,
                            Colors.orange,
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => WarehouseLayoutScreen(
                                  allProducts: context
                                      .read<ProductProvider>()
                                      .products,
                                ),
                              ),
                            ),
                            child: _buildInfoItem(
                              Icons.location_on_rounded,
                              "Vị trí kho",
                              p.layoutPosition,
                              Colors.redAccent,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _buildInfoItem(
                            Icons.query_stats_rounded,
                            "Số lượng tồn",
                            NumberFormat('#,###', 'vi_VN').format(
                              context.read<ProductProvider>().getCurrentStock(
                                p,
                                context.read<SettingsProvider>().stockSource,
                              ),
                            ),
                            Colors.blueAccent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
    String label,
    String value,
    IconData icon,
    Color color, {
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(right: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: color.withOpacity(0.15), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductThumbnail(String? path) {
    if (path == null || path.isEmpty) {
      return Container(
        color: Colors.grey[200],
        child: const Icon(Icons.image_not_supported, color: Colors.grey),
      );
    }
    final fullUrl = path.startsWith('http')
        ? path
        : '${ApiService().uploadUrl}$path';
    return Image.network(
      fullUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        color: Colors.grey[200],
        child: const Icon(Icons.broken_image, color: Colors.grey),
      ),
    );
  }

  Widget _buildInfoItem(
    IconData icon,
    String label,
    String value,
    Color iconColor,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 10,
                color: Colors.grey[600],
                letterSpacing: 0.5,
              ),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ],
    );
  }
}

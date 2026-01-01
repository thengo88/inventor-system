import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../providers/product_provider.dart';
import '../providers/settings_provider.dart';

class ProductDetailScreen extends StatelessWidget {
  final Product product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<ProductProvider>();
    final images = [
      if (product.imageUrl != null && product.imageUrl!.isNotEmpty)
        provider.getFullImageUrl(product.imageUrl),
      if (product.imageUrl2 != null && product.imageUrl2!.isNotEmpty)
        provider.getFullImageUrl(product.imageUrl2),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết sản phẩm')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            // Tablet / PC View
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        if (images.isNotEmpty)
                          _buildImageSlider(images)
                        else
                          _buildPlaceholderImage(),
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 6,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoCard(context),
                        const SizedBox(height: 32),
                        _buildSection(
                          context,
                          'Mã số (SKU)',
                          product.sku,

                          Icons.tag,
                        ),
                        _buildSection(
                          context,
                          'Tên sản phẩm',
                          product.name,
                          Icons.inventory_2_outlined,
                        ),
                        _buildSection(
                          context,
                          'Tiêu chuẩn đóng gói',
                          product.packagingStandard,
                          Icons.inventory_2_outlined,
                        ),
                        _buildSection(
                          context,
                          'Vị trí trên layout',
                          product.layoutPosition,
                          Icons.map_outlined,
                        ),
                        _buildSection(
                          context,
                          'Khách hàng',
                          product.customer,
                          Icons.person_outline,
                        ),
                        _buildSection(
                          context,
                          'Số lượng tồn kho',
                          NumberFormat('#,###', 'vi_VN').format(
                            context.watch<ProductProvider>().getCurrentStock(
                              product,
                              context.read<SettingsProvider>().stockSource,
                            ),
                          ),
                          Icons.inventory_2_outlined,
                        ),
                        if (product.description != null &&
                            product.description!.isNotEmpty)
                          _buildSection(
                            context,
                            'Mô tả sản phẩm',
                            product.description!,
                            Icons.description_outlined,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          } else {
            // Mobile View
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (images.isNotEmpty)
                    _buildImageSlider(images)
                  else
                    _buildPlaceholderImage(),
                  const SizedBox(height: 32),
                  _buildInfoCard(context),
                  const SizedBox(height: 32),
                  _buildSection(context, 'Mã số (SKU)', product.sku, Icons.tag),
                  _buildSection(
                    context,
                    'Tên sản phẩm',
                    product.name,
                    Icons.inventory_2_outlined,
                  ),
                  _buildSection(
                    context,
                    'Tiêu chuẩn đóng gói',
                    product.packagingStandard,
                    Icons.inventory_2_outlined,
                  ),
                  _buildSection(
                    context,
                    'Vị trí trên layout',
                    product.layoutPosition,
                    Icons.map_outlined,
                  ),
                  _buildSection(
                    context,
                    'Khách hàng',
                    product.customer,
                    Icons.person_outline,
                  ),
                  _buildSection(
                    context,
                    'Số lượng tồn kho',
                    NumberFormat('#,###', 'vi_VN').format(
                      context.watch<ProductProvider>().getCurrentStock(
                        product,
                        context.read<SettingsProvider>().stockSource,
                      ),
                    ),
                    Icons.inventory_2_outlined,
                  ),
                  if (product.description != null &&
                      product.description!.isNotEmpty)
                    _buildSection(
                      context,
                      'Mô tả sản phẩm',
                      product.description!,
                      Icons.description_outlined,
                    ),
                ],
              ),
            );
          }
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showStockInput(context, product),
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Nhập hàng'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showStockInput(BuildContext context, Product product) {
    final TextEditingController stockInCtrl = TextEditingController();
    bool isAdditive = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Nhập hàng: ${product.sku}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tồn hiện tại: ${NumberFormat('#,###', 'vi_VN').format(product.stock)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: stockInCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: isAdditive
                      ? 'Số lượng nhập thêm'
                      : 'Số lượng tồn mới',
                  border: const OutlineInputBorder(),
                  prefixIcon: Icon(
                    isAdditive ? Icons.add_circle_outline : Icons.edit_note,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: !isAdditive,
                    onChanged: (val) {
                      setDialogState(() {
                        isAdditive = !(val ?? false);
                      });
                    },
                  ),
                  const Expanded(
                    child: Text('Ghi đè tổng tồn kho (Thay vì cộng thêm)'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () async {
                final valString = stockInCtrl.text.trim();
                if (valString.isEmpty) return;
                final val = double.tryParse(valString);
                if (val == null) return;

                final newStock = isAdditive ? (product.stock + val) : val;

                final newProduct = Product(
                  id: product.id,
                  sku: product.sku,
                  name: product.name,
                  packagingStandard: product.packagingStandard,
                  imageUrl: product.imageUrl,
                  imageUrl2: product.imageUrl2,
                  layoutPosition: product.layoutPosition,
                  customer: product.customer,
                  description: product.description,
                  stock: newStock,
                );

                final success = await context
                    .read<ProductProvider>()
                    .updateStock(newProduct, val, isAdditive);

                if (context.mounted) {
                  Navigator.pop(context);
                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isAdditive
                              ? 'Đã nhập thêm $val. Tổng tồn mới: $newStock'
                              : 'Đã cập nhật tồn kho thành: $val',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              },
              child: const Text('Xác nhận'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSlider(List<String> images) {
    if (images.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Image.network(
          images[0],
          width: double.infinity,
          height: 300,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildPlaceholderImage(),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 300,
          child: PageView.builder(
            itemCount: images.length,
            controller: PageController(viewportFraction: 0.96),
            itemBuilder: (context, index) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.network(
                    images[index],
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, __, ___) => _buildPlaceholderImage(),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            images.length,
            (index) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withOpacity(0.5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      width: double.infinity,
      height: 250,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(24),
      ),
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 64,
        color: Colors.grey[400],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_done_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Dữ liệu được lấy trực tiếp từ máy chủ hệ thống.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
        ],
      ),
    );
  }
}

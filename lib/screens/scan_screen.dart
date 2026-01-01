import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../providers/product_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/scanner_widgets.dart';
import 'product_detail_screen.dart';
import '../models/product.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool isScanning = true;
  final TextEditingController _manualSkuController = TextEditingController();

  @override
  void dispose() {
    _manualSkuController.dispose();
    super.dispose();
  }

  Future<void> _processSku(String code) async {
    if (!isScanning) return;
    setState(() => isScanning = false);

    // Xử lý mã QR theo yêu cầu
    String processedCode = code.replaceAll('-', '');

    // 1. Bỏ toàn bộ ký tự từ dấu ; đến hết
    if (processedCode.contains(';')) {
      processedCode = processedCode.split(';')[0];
    }

    // 2. Nếu mã bắt đầu bằng chữ (VD: A00BB...), bỏ 5 ký tự đầu
    if (processedCode.isNotEmpty &&
        RegExp(r'^[A-Za-z]').hasMatch(processedCode)) {
      if (processedCode.length > 5) {
        processedCode = processedCode.substring(5);
      }
    }

    await _handleSkuLookup(processedCode);
  }

  Future<void> _handleSkuLookup(String sku) async {
    final product = await context.read<ProductProvider>().scanProduct(sku);

    if (mounted) {
      if (product != null) {
        _showProductOptions(product);
      } else {
        _showError(sku);
      }
    }
  }

  void _showProductOptions(Product product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              product.sku,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              product.name,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Tồn kho: ${NumberFormat('#,###', 'vi_VN').format(context.read<ProductProvider>().getCurrentStock(product, context.read<SettingsProvider>().stockSource))}',
                style: TextStyle(
                  color: Colors.blue[900],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Vị trí: ${product.layoutPosition}',
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: _buildOptionButton(
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProductDetailScreen(product: product),
                        ),
                      ).then((_) => setState(() => isScanning = true));
                    },
                    icon: Icons.info_outline,
                    label: 'Xem thông tin',
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildOptionButton(
                    onTap: () {
                      Navigator.pop(context);
                      _showStockInput(product);
                    },
                    icon: Icons.add_business_outlined,
                    label: 'Nhập thêm hàng',
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() => isScanning = true);
              },
              child: const Text('Hủy', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    ).then((_) {
      if (mounted && !isScanning) {
        // Auto-resume logic if needed
      }
    });
  }

  Widget _buildOptionButton({
    required VoidCallback onTap,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  void _showStockInput(Product product) {
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
              onPressed: () {
                Navigator.pop(context);
                setState(() => isScanning = true);
              },
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () async {
                final val = double.tryParse(stockInCtrl.text);
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
                if (mounted) {
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
                  setState(() => isScanning = true);
                }
              },
              child: const Text('Xác nhận'),
            ),
          ],
        ),
      ),
    );
  }

  void _showManualInput() {
    setState(() => isScanning = false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Nhập mã thủ công'),
        content: TextField(
          controller: _manualSkuController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Mã sản phẩm (SKU)',
            hintText: 'VD: 12206',
            prefixIcon: Icon(Icons.edit_note),
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        actions: [
          Row(
            children: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() => isScanning = true);
                },
                child: const Text('Hủy'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  final code = _manualSkuController.text.trim();
                  Navigator.pop(context);
                  if (code.isNotEmpty) {
                    _showAddNewProduct(code);
                  } else {
                    setState(() => isScanning = true);
                  }
                },
                child: const Text(
                  'Thêm mới',
                  style: TextStyle(color: Colors.green),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  final code = _manualSkuController.text.trim();
                  if (code.isNotEmpty) {
                    Navigator.pop(context);
                    _handleSkuLookup(code);
                  }
                },
                child: const Text('Tìm kiếm'),
              ),
            ],
          ),
        ],
      ),
    ).then((_) {
      _manualSkuController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (!isScanning) return;
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final code = barcodes.first.rawValue;
                if (code != null) {
                  _processSku(code);
                }
              }
            },
            errorBuilder: (context, error) => const Center(
              child: Text('Lỗi camera', style: TextStyle(color: Colors.white)),
            ),
          ),

          _buildPremiumOverlay(),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'NHẬP KHO',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard, color: Colors.white),
                    onPressed: _showManualInput,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumOverlay() {
    return Stack(
      children: [
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
        Center(
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.blue.withOpacity(0.5), width: 1),
              borderRadius: BorderRadius.circular(24),
            ),
            child: CustomPaint(
              painter: ScannerCornerPainter(color: Colors.blue),
            ),
          ),
        ),
        Positioned(
          bottom: 100,
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
                    Icon(Icons.camera_alt, color: Colors.blue, size: 20),
                    Text(
                      'Đưa mã vào khung hình',
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
        const ScanningAnimation(width: 260),
      ],
    );
  }

  void _showError(String code) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 10),
            Text('Sản phẩm chưa có'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mã sản phẩm: $code'),
            const SizedBox(height: 8),
            const Text(
              'Sản phẩm này chưa có trong hệ thống. Bạn có muốn thêm mới không?',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => isScanning = true);
            },
            child: const Text('Quét lại'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _showAddNewProduct(code);
            },
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Thêm mới'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddNewProduct(String sku) {
    final TextEditingController nameCtrl = TextEditingController();
    final TextEditingController stockCtrl = TextEditingController();
    final TextEditingController packagingCtrl = TextEditingController();
    final TextEditingController layoutCtrl = TextEditingController();
    final TextEditingController customerCtrl = TextEditingController();
    final TextEditingController descriptionCtrl = TextEditingController();

    File? selectedImage1;
    File? selectedImage2;

    Future<void> pickImage(int index, StateSetter setDialogState) async {
      await showModalBottomSheet(
        context: context,
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Chụp ảnh mới'),
              onTap: () async {
                Navigator.pop(ctx);
                final ImagePicker picker = ImagePicker();
                final XFile? image = await picker.pickImage(
                  source: ImageSource.camera,
                );
                if (image != null) {
                  setDialogState(() {
                    if (index == 1) {
                      selectedImage1 = File(image.path);
                    } else {
                      selectedImage2 = File(image.path);
                    }
                  });
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Chọn từ thư viện'),
              onTap: () async {
                Navigator.pop(ctx);
                final ImagePicker picker = ImagePicker();
                final XFile? image = await picker.pickImage(
                  source: ImageSource.gallery,
                );
                if (image != null) {
                  setDialogState(() {
                    if (index == 1) {
                      selectedImage1 = File(image.path);
                    } else {
                      selectedImage2 = File(image.path);
                    }
                  });
                }
              },
            ),
          ],
        ),
      );
    }

    Widget buildImagePicker(
      int index,
      File? image,
      StateSetter setDialogState,
    ) {
      return GestureDetector(
        onTap: () => pickImage(index, setDialogState),
        child: Container(
          height: 100,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: image != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(image, fit: BoxFit.cover),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo, color: Colors.grey[400], size: 32),
                    const SizedBox(height: 4),
                    Text(
                      index == 1 ? 'Ảnh mặt trước' : 'Ảnh chi tiết',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
        ),
      );
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text('Thêm sản phẩm mới'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Image pickers
                  Row(
                    children: [
                      Expanded(
                        child: buildImagePicker(
                          1,
                          selectedImage1,
                          setDialogState,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: buildImagePicker(
                          2,
                          selectedImage2,
                          setDialogState,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: TextEditingController(text: sku),
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: 'Mã sản phẩm (SKU)',
                      prefixIcon: Icon(Icons.qr_code),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Tên sản phẩm *',
                      prefixIcon: Icon(Icons.inventory_2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: stockCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Số lượng nhập kho *',
                      prefixIcon: Icon(Icons.add_box),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: packagingCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tiêu chuẩn đóng gói',
                      prefixIcon: Icon(Icons.inventory),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: layoutCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Vị trí trên layout',
                      prefixIcon: Icon(Icons.location_on),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: customerCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Khách hàng',
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Mô tả sản phẩm',
                      prefixIcon: Icon(Icons.description),
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() => isScanning = true);
                },
                child: const Text('Hủy'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty ||
                      stockCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Vui lòng nhập tên và số lượng!'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  final stock = double.tryParse(stockCtrl.text.trim()) ?? 0;
                  final newProduct = Product(
                    sku: sku,
                    name: nameCtrl.text.trim(),
                    packagingStandard: packagingCtrl.text.trim(),
                    layoutPosition: layoutCtrl.text.trim(),
                    customer: customerCtrl.text.trim(),
                    description: descriptionCtrl.text.trim(),
                    stock: stock,
                  );

                  final success = await context
                      .read<ProductProvider>()
                      .addProduct(newProduct, selectedImage1, selectedImage2);

                  if (mounted) {
                    Navigator.pop(context);
                    if (success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã thêm sản phẩm $sku với $stock đơn vị!',
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                    setState(() => isScanning = true);
                  }
                },
                child: const Text('Lưu'),
              ),
            ],
          );
        },
      ),
    );
  }
}

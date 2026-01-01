import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../providers/product_provider.dart';

class EditProductScreen extends StatefulWidget {
  final Product? product;

  const EditProductScreen({super.key, this.product});

  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _skuController;
  late TextEditingController _nameController;
  late TextEditingController _packagingController;
  late TextEditingController _layoutController;
  late TextEditingController _customerController;
  late TextEditingController _descriptionController;
  late TextEditingController _stockController;
  File? _selectedImageFile;
  File? _selectedImageFile2;
  String? _remoteImageUrl;
  String? _remoteImageUrl2;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _skuController = TextEditingController(text: widget.product?.sku);
    _nameController = TextEditingController(text: widget.product?.name);
    _packagingController = TextEditingController(
      text: widget.product?.packagingStandard,
    );
    _layoutController = TextEditingController(
      text: widget.product?.layoutPosition,
    );
    _customerController = TextEditingController(text: widget.product?.customer);
    _descriptionController = TextEditingController(
      text: widget.product?.description,
    );
    _stockController = TextEditingController(
      text: widget.product?.stock.toString() ?? '0',
    );
    _remoteImageUrl = widget.product?.imageUrl;
    _remoteImageUrl2 = widget.product?.imageUrl2;
  }

  @override
  void dispose() {
    _skuController.dispose();
    _nameController.dispose();
    _packagingController.dispose();
    _layoutController.dispose();
    _customerController.dispose();
    _descriptionController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(int index) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        if (index == 1) {
          _selectedImageFile = File(image.path);
          _remoteImageUrl = null;
        } else {
          _selectedImageFile2 = File(image.path);
          _remoteImageUrl2 = null;
        }
      });
    }
  }

  void _save() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);

      final product = Product(
        id: widget.product?.id,
        sku: _skuController.text.trim(),
        name: _nameController.text.trim(),
        packagingStandard: _packagingController.text.trim(),
        layoutPosition: _layoutController.text.trim(),
        customer: _customerController.text.trim(),
        description: _descriptionController.text.trim(),
        stock: double.tryParse(_stockController.text.trim()) ?? 0.0,
        imageUrl: widget.product?.imageUrl,
        imageUrl2: widget.product?.imageUrl2,
      );

      final provider = context.read<ProductProvider>();
      if (widget.product == null) {
        await provider.addProduct(
          product,
          _selectedImageFile,
          _selectedImageFile2,
        );
      } else {
        await provider.updateProduct(
          product,
          _selectedImageFile,
          _selectedImageFile2,
        );
      }

      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.product == null
                  ? 'Đã thêm sản phẩm thành công'
                  : 'Đã cập nhật sản phẩm thành công',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isEdit = widget.product != null;
    final provider = context.read<ProductProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Sửa sản phẩm' : 'Thêm sản phẩm (Server)'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildImagePicker(
                      index: 1,
                      file: _selectedImageFile,
                      remoteUrl: _remoteImageUrl,
                      label: 'Ảnh mặt trước',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildImagePicker(
                      index: 2,
                      file: _selectedImageFile2,
                      remoteUrl: _remoteImageUrl2,
                      label: 'Ảnh chi tiết',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('Thông tin cơ bản'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      controller: _skuController,
                      label: 'Mã số (SKU)',
                      icon: Icons.tag,
                      validator: (v) => v!.isEmpty ? 'Vui lòng nhập SKU' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildField(
                      controller: _nameController,
                      label: 'Tên sản phẩm',
                      icon: Icons.inventory_2_outlined,
                      validator: (v) => v!.isEmpty ? 'Vui lòng nhập tên' : null,
                    ),
                  ),
                ],
              ),
              _buildSectionTitle('Thông tin chi tiết'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      controller: _packagingController,
                      label: 'Tiêu chuẩn đóng gói',
                      icon: Icons.inventory_2_outlined,
                      validator: (v) =>
                          v!.isEmpty ? 'Vui lòng nhập tiêu chuẩn' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildField(
                      controller: _layoutController,
                      label: 'Vị trí trên layout',
                      icon: Icons.map_outlined,
                      validator: (v) =>
                          v!.isEmpty ? 'Vui lòng nhập vị trí' : null,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      controller: _customerController,
                      label: 'Khách hàng',
                      icon: Icons.person_outline,
                      validator: (v) =>
                          v!.isEmpty ? 'Vui lòng nhập khách hàng' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildField(
                      controller: _stockController,
                      label: 'Số lượng tồn kho',
                      icon: Icons.inventory,
                      keyboardType: TextInputType.number,
                      validator: (v) =>
                          v!.isEmpty ? 'Vui lòng nhập số lượng' : null,
                    ),
                  ),
                ],
              ),
              _buildField(
                controller: _descriptionController,
                label: 'Mô tả sản phẩm',
                icon: Icons.description_outlined,
                maxLines: 3,
                validator: null,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          isEdit ? 'Cập nhật Server' : 'Lưu lên Server',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePicker({
    required int index,
    File? file,
    String? remoteUrl,
    required String label,
  }) {
    final provider = context.read<ProductProvider>();
    return Column(
      children: [
        GestureDetector(
          onTap: () => _pickImage(index),
          child: Container(
            height: 100,
            width: double.infinity,
            decoration: BoxDecoration(
              color: file != null || (remoteUrl != null && remoteUrl.isNotEmpty)
                  ? Colors.grey[100]
                  : Colors.blue[50]?.withOpacity(0.3),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color:
                    file != null || (remoteUrl != null && remoteUrl.isNotEmpty)
                    ? Colors.blue.withOpacity(0.3)
                    : Colors.grey[200]!,
                width: 2,
                style: BorderStyle.solid,
              ),
            ),
            child: file != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.file(file, fit: BoxFit.cover),
                  )
                : (remoteUrl != null && remoteUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.network(
                            provider.getFullImageUrl(remoteUrl),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _buildPlaceholder(label),
                          ),
                        )
                      : _buildPlaceholder(label)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: Colors.blue,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder(String label) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_a_photo_outlined, size: 24, color: Colors.blue[300]),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Chọn ảnh',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Colors.blue[300],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        validator: validator,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[200]!),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }
}

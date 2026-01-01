class Product {
  final int? id;
  String sku;
  final String? skuPlain;
  String name;
  final String packagingStandard;
  final String? imageUrl;
  final String? imageUrl2;
  final String layoutPosition;
  final String customer;
  final String? description;
  final double stock;

  Product({
    this.id,
    required this.sku,
    this.skuPlain,
    required this.name,
    required this.packagingStandard,
    this.imageUrl,
    this.imageUrl2,
    required this.layoutPosition,
    required this.customer,
    this.description,
    this.stock = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sku': sku,
      'sku_plain': skuPlain,
      'name': name,
      'packagingStandard': packagingStandard,
      'imageUrl': imageUrl,
      'imageUrl2': imageUrl2,
      'layoutPosition': layoutPosition,
      'customer': customer,
      'description': description,
      'stock': stock,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      sku: map['sku'],
      skuPlain: map['sku_plain'],
      name: map['name'],
      packagingStandard: map['packagingStandard'],
      imageUrl: map['imageUrl'],
      imageUrl2: map['imageUrl2'],
      layoutPosition: map['layoutPosition'],
      customer: map['customer'],
      description: map['description'],
      stock: (map['stock'] ?? 0.0).toDouble(),
    );
  }
}

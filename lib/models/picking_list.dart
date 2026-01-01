class PickingList {
  final int? id;
  final String orderNumber;
  final String customer;
  final String status;
  final DateTime createdAt;
  final int? totalItems;
  final int? totalQtyRequired;
  final int? totalQtyPicked;
  List<PickingItem>? items;

  PickingList({
    this.id,
    required this.orderNumber,
    required this.customer,
    required this.status,
    required this.createdAt,
    this.totalItems,
    this.totalQtyRequired,
    this.totalQtyPicked,
    this.items,
  });

  factory PickingList.fromMap(Map<String, dynamic> map) {
    return PickingList(
      id: map['id'],
      orderNumber: map['orderNumber'] ?? 'N/A',
      customer: map['customer'] ?? 'Không tên',
      status: map['status'] ?? 'pending',
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt']) ?? DateTime.now()
          : DateTime.now(),
      totalItems: map['totalItems'],
      totalQtyRequired: map['totalQtyRequired'],
      totalQtyPicked: map['totalQtyPicked'],
      items: map['items'] != null
          ? (map['items'] as List).map((i) => PickingItem.fromMap(i)).toList()
          : [],
    );
  }
}

class PickingItem {
  final int? id;
  final int? pickingListId;
  String sku;
  final String? skuPlain;
  String productName;
  final int quantityRequired;
  int quantityPicked;
  final String? gate;
  final String? line;
  final String? zone;
  final String? rec_hh;
  final String? tr_no;
  final String? odr_typ;
  final String? box;
  final String? ps_cd;
  final String? rec_opr;
  final String? assignedUser;
  String? imageUrl;
  String? imageUrl2;
  String? packagingStandard;
  String? description;

  PickingItem({
    this.id,
    this.pickingListId,
    required this.sku,
    this.skuPlain,
    required this.productName,
    required this.quantityRequired,
    required this.quantityPicked,
    this.gate,
    this.line,
    this.zone,
    this.rec_hh,
    this.tr_no,
    this.odr_typ,
    this.box,
    this.ps_cd,
    this.rec_opr,
    this.assignedUser,
    this.imageUrl,
    this.imageUrl2,
    this.packagingStandard,
    this.description,
  });

  factory PickingItem.fromMap(Map<String, dynamic> map) {
    return PickingItem(
      id: map['id'],
      pickingListId: map['pickingListId'],
      sku: map['sku'] ?? 'N/A',
      skuPlain: map['sku_plain'],
      productName: map['productName'] ?? 'Sản phẩm không tên',
      quantityRequired: map['quantityRequired'] ?? 0,
      quantityPicked: map['quantityPicked'] ?? 0,
      gate: map['gate']?.toString(),
      line: map['line']?.toString(),
      zone: map['zone']?.toString(),
      rec_hh: map['rec_hh']?.toString(),
      tr_no: map['tr_no']?.toString(),
      odr_typ: map['odr_typ']?.toString(),
      box: map['box']?.toString(),
      ps_cd: map['ps_cd']?.toString(),
      rec_opr: map['rec_opr']?.toString(),
      assignedUser: map['assigned_user']?.toString(),
      imageUrl: map['imageUrl']?.toString(),
      imageUrl2: map['imageUrl2']?.toString(),
      packagingStandard: map['packagingStandard']?.toString(),
      description: map['description']?.toString(),
    );
  }
}

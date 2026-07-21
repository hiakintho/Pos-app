// We now use Strings for roles to allow dynamic creation
class UserRole {
  static const String superAdmin = 'super_admin';
  static const String supervisor = 'supervisor';
  static const String cashier = 'cashier';
  static const String supplier = 'supplier';
  static const String customer = 'customer';
  static const String deliveryBoy = 'delivery_boy';
  static const String systemOwner = 'system_owner';
}

class RolePermissions {
  final String roleId;
  final String displayName;
  final Map<String, bool> permissions;

  RolePermissions({
    required this.roleId,
    required this.displayName,
    required this.permissions,
  });

  Map<String, dynamic> toMap() {
    return {
      'roleId': roleId,
      'displayName': displayName,
      'permissions': permissions,
    };
  }

  factory RolePermissions.fromMap(Map<String, dynamic> map) {
    return RolePermissions(
      roleId: map['roleId'] ?? '',
      displayName: map['displayName'] ?? '',
      permissions: Map<String, bool>.from(map['permissions'] ?? {}),
    );
  }

  static RolePermissions defaultFor(String roleId) {
    String name = roleId.replaceAll('_', ' ').toUpperCase();
    Map<String, bool> perms = {
      'Access POS': true,
      'Access Inventory': false,
      'Access Reports': false,
      'Manage Users': false,
      'Manage Settings': false,
    };

    if (roleId == UserRole.superAdmin) {
      perms.updateAll((key, value) => true);
    } else if (roleId == UserRole.supervisor) {
      perms['Access Inventory'] = true;
      perms['Access Reports'] = true;
    } else if (roleId == UserRole.supplier) {
      perms['Access POS'] = false;
      perms['Access Inventory'] = true;
    }

    return RolePermissions(
      roleId: roleId,
      displayName: name,
      permissions: perms,
    );
  }
}

class User {
  final String id;
  final String name;
  final String email;
  final String role; // Changed from Enum to String
  final String? branchId;
  final String? businessId;
  final bool requiresEmailVerification;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.branchId,
    this.businessId,
    this.requiresEmailVerification = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'role': role,
      'branchId': branchId,
      'businessId': businessId,
      'requiresEmailVerification': requiresEmailVerification,
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    // Handle migration from legacy int roles to new String roles
    dynamic roleData = map['role'];
    String finalRole = UserRole.cashier;

    if (roleData is int) {
      // Mapping old enum indices to new string IDs
      const legacyRoles = [
        UserRole.superAdmin,
        UserRole.supervisor,
        UserRole.cashier,
        UserRole.supplier,
      ];
      if (roleData >= 0 && roleData < legacyRoles.length) {
        finalRole = legacyRoles[roleData];
      }
    } else if (roleData is String) {
      finalRole = roleData;
    }

    return User(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      role: finalRole,
      branchId: map['branchId'],
      businessId: map['businessId'],
      requiresEmailVerification: map['requiresEmailVerification'] == true,
    );
  }
}

class Branch {
  final String id;
  final String name;
  final String address;
  final String phone;
  final String managerId;
  final String? businessId;

  Branch({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
    required this.managerId,
    this.businessId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'phone': phone,
      'managerId': managerId,
      'businessId': businessId,
    };
  }

  factory Branch.fromMap(Map<String, dynamic> map) {
    return Branch(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      address: map['address'] ?? '',
      phone: map['phone'] ?? '',
      managerId: map['managerId'] ?? '',
      businessId: map['businessId'],
    );
  }
}

class Product {
  final String id;
  final String name;
  final String barcode;
  final double price;
  final double productCost;
  final double stockQuantity;
  final String category;
  final String? priceGroupId;
  final String? brandName;
  final String? unitOfMeasurement;
  final String? supplierId;
  final String? supplierName;
  final String? taxRuleId;
  final String? branchId;
  final String? businessId;
  final String? batchNumber;
  final String? expiryDate;
  final String? manufacturingDate;
  final String? description;
  final List<String> aliases;
  final bool isAvailableOnline;
  final String? shopName;
  final String? lipaNumber;
  final List<String> imageUrls;
  final bool freeShipping;
  final double shippingFee;
  final String paymentTiming;
  final String paymentAmountPolicy;
  final int isSynced;

  Product({
    required this.id,
    required this.name,
    required this.barcode,
    required this.price,
    this.productCost = 0,
    required this.stockQuantity,
    required this.category,
    this.priceGroupId,
    this.brandName,
    this.unitOfMeasurement,
    this.supplierId,
    this.supplierName,
    this.taxRuleId,
    this.branchId,
    this.businessId,
    this.batchNumber,
    this.expiryDate,
    this.manufacturingDate,
    this.description,
    this.aliases = const [],
    this.isAvailableOnline = false,
    this.shopName,
    this.lipaNumber,
    this.imageUrls = const [],
    this.freeShipping = true,
    this.shippingFee = 0,
    this.paymentTiming = 'business_default',
    this.paymentAmountPolicy = 'business_default',
    this.isSynced = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'barcode': barcode,
      'price': price,
      'productCost': productCost,
      'stockQuantity': stockQuantity,
      'category': category,
      'priceGroupId': priceGroupId,
      'brandName': brandName,
      'unitOfMeasurement': unitOfMeasurement,
      'supplierId': supplierId,
      'supplierName': supplierName,
      'taxRuleId': taxRuleId,
      'branchId': branchId,
      'businessId': businessId,
      'batchNumber': batchNumber,
      'expiryDate': expiryDate,
      'manufacturingDate': manufacturingDate,
      'description': description,
      'aliases': aliases.join(','),
      'isAvailableOnline': isAvailableOnline,
      'shopName': shopName,
      'lipaNumber': lipaNumber,
      'imageUrls': imageUrls.join(','),
      'freeShipping': freeShipping,
      'shippingFee': shippingFee,
      'paymentTiming': paymentTiming,
      'paymentAmountPolicy': paymentAmountPolicy,
      'isSynced': isSynced,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: _stringValue(map['id']),
      name: _stringValue(map['name'], fallback: 'Unnamed product'),
      barcode: _stringValue(map['barcode']),
      price: _doubleValue(map['price']),
      productCost: _doubleValue(map['productCost']),
      stockQuantity: _doubleValue(map['stockQuantity']),
      category: _stringValue(map['category'], fallback: 'General'),
      priceGroupId: _nullableStringValue(map['priceGroupId']),
      brandName: _nullableStringValue(map['brandName']),
      unitOfMeasurement: _nullableStringValue(map['unitOfMeasurement']),
      supplierId: _nullableStringValue(map['supplierId']),
      supplierName: _nullableStringValue(map['supplierName']),
      taxRuleId: _nullableStringValue(map['taxRuleId']),
      branchId: _nullableStringValue(map['branchId']),
      businessId: _nullableStringValue(map['businessId']),
      batchNumber: _nullableStringValue(map['batchNumber']),
      expiryDate: _nullableStringValue(map['expiryDate']),
      manufacturingDate: _nullableStringValue(map['manufacturingDate']),
      description: _nullableStringValue(map['description']),
      aliases: _stringListValue(map['aliases']),
      isAvailableOnline:
          map['isAvailableOnline'] == true || map['isAvailableOnline'] == 1,
      shopName: _nullableStringValue(map['shopName']),
      lipaNumber: _nullableStringValue(map['lipaNumber']),
      imageUrls: _stringListValue(map['imageUrls']),
      freeShipping: map['freeShipping'] != false,
      shippingFee: _doubleValue(map['shippingFee']),
      paymentTiming: _stringValue(
        map['paymentTiming'],
        fallback: 'business_default',
      ),
      paymentAmountPolicy: _stringValue(
        map['paymentAmountPolicy'],
        fallback: 'business_default',
      ),
      isSynced: map['isSynced'] ?? 0,
    );
  }
}

class CartItem {
  final Product product;
  int quantity;
  double unitPrice;
  double discountAmount;
  double taxAmount;
  String pricingNote;

  CartItem({
    required this.product,
    this.quantity = 1,
    double? unitPrice,
    this.discountAmount = 0,
    this.taxAmount = 0,
    this.pricingNote = '',
  }) : unitPrice = unitPrice ?? product.price;

  double get subtotal => unitPrice * quantity;
  double get total => subtotal - discountAmount + taxAmount;
}

class ProductCategory {
  final String id;
  final String name;
  final String description;
  final String businessId;

  const ProductCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.businessId,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'businessId': businessId,
  };

  factory ProductCategory.fromMap(Map<String, dynamic> map) {
    return ProductCategory(
      id: _stringValue(map['id']),
      name: _stringValue(map['name'], fallback: 'General'),
      description: _stringValue(map['description']),
      businessId: _stringValue(map['businessId'], fallback: 'default_business'),
    );
  }
}

String _stringValue(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

String? _nullableStringValue(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

double _doubleValue(dynamic value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? fallback;
  return fallback;
}

List<String> _stringListValue(dynamic value) {
  if (value is Iterable) {
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
  }
  if (value is String) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return const [];
}

class PriceGroup {
  final String id;
  final String name;
  final String type;
  final double value;
  final List<String> productIds;
  final List<String> categories;
  final bool isActive;
  final String businessId;

  const PriceGroup({
    required this.id,
    required this.name,
    required this.type,
    required this.value,
    required this.productIds,
    required this.categories,
    required this.isActive,
    required this.businessId,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'type': type,
    'value': value,
    'productIds': productIds,
    'categories': categories,
    'isActive': isActive,
    'businessId': businessId,
  };

  factory PriceGroup.fromMap(Map<String, dynamic> map) {
    return PriceGroup(
      id: _stringValue(map['id']),
      name: _stringValue(map['name'], fallback: 'Price group'),
      type: _stringValue(map['type'], fallback: 'discount_percent'),
      value: _doubleValue(map['value']),
      productIds: _stringListValue(map['productIds']),
      categories: _stringListValue(map['categories']),
      isActive: map['isActive'] != false,
      businessId: _stringValue(map['businessId'], fallback: 'default_business'),
    );
  }
}

class TaxRule {
  final String id;
  final String name;
  final double rate;
  final String targetType;
  final String? priceGroupId;
  final List<String> productIds;
  final List<String> categories;
  final bool isActive;
  final String businessId;

  const TaxRule({
    required this.id,
    required this.name,
    required this.rate,
    required this.targetType,
    this.priceGroupId,
    required this.productIds,
    required this.categories,
    required this.isActive,
    required this.businessId,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'rate': rate,
    'targetType': targetType,
    'priceGroupId': priceGroupId,
    'productIds': productIds,
    'categories': categories,
    'isActive': isActive,
    'businessId': businessId,
  };

  factory TaxRule.fromMap(Map<String, dynamic> map) {
    return TaxRule(
      id: _stringValue(map['id']),
      name: _stringValue(map['name'], fallback: 'Tax'),
      rate: _doubleValue(map['rate']),
      targetType: _stringValue(map['targetType'], fallback: 'category'),
      priceGroupId: _nullableStringValue(map['priceGroupId']),
      productIds: _stringListValue(map['productIds']),
      categories: _stringListValue(map['categories']),
      isActive: map['isActive'] != false,
      businessId: _stringValue(map['businessId'], fallback: 'default_business'),
    );
  }
}

class Sale {
  final String id;
  final String itemsJson;
  final double totalAmount;
  final String timestamp;
  final String branchId;
  final String cashierId;
  final String paymentMethod;
  final double paidAmount;
  final double changeAmount;
  final double discountAmount;
  final double taxAmount;
  final bool isCredit;
  final String? customerName;
  final String status;
  final int isSynced;

  Sale({
    required this.id,
    required this.itemsJson,
    required this.totalAmount,
    required this.timestamp,
    required this.branchId,
    required this.cashierId,
    required this.paymentMethod,
    this.paidAmount = 0,
    this.changeAmount = 0,
    this.discountAmount = 0,
    this.taxAmount = 0,
    this.isCredit = false,
    this.customerName,
    this.status = 'completed',
    this.isSynced = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'itemsJson': itemsJson,
      'totalAmount': totalAmount,
      'timestamp': timestamp,
      'branchId': branchId,
      'cashierId': cashierId,
      'paymentMethod': paymentMethod,
      'paidAmount': paidAmount,
      'changeAmount': changeAmount,
      'discountAmount': discountAmount,
      'taxAmount': taxAmount,
      'isCredit': isCredit ? 1 : 0,
      'customerName': customerName,
      'status': status,
      'isSynced': isSynced,
    };
  }

  factory Sale.fromMap(Map<String, dynamic> map) {
    return Sale(
      id: _stringValue(map['id']),
      itemsJson: _stringValue(map['itemsJson'], fallback: '[]'),
      totalAmount: _doubleValue(map['totalAmount']),
      timestamp: _stringValue(
        map['timestamp'],
        fallback: DateTime.now().toIso8601String(),
      ),
      branchId: _stringValue(map['branchId'], fallback: 'main'),
      cashierId: _stringValue(map['cashierId']),
      paymentMethod: _stringValue(map['paymentMethod'], fallback: 'Cash'),
      paidAmount: _doubleValue(map['paidAmount']),
      changeAmount: _doubleValue(map['changeAmount']),
      discountAmount: _doubleValue(map['discountAmount']),
      taxAmount: _doubleValue(map['taxAmount']),
      isCredit: map['isCredit'] == true || map['isCredit'] == 1,
      customerName: _nullableStringValue(map['customerName']),
      status: _stringValue(map['status'], fallback: 'completed'),
      isSynced: map['isSynced'] ?? 0,
    );
  }
}

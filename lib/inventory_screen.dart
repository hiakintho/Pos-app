import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'app_loading_indicator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'models.dart';
import 'notification_inbox_page.dart';

class InventoryScreen extends StatefulWidget {
  final User user;
  final VoidCallback? onOpenMenu;
  const InventoryScreen({super.key, required this.user, this.onOpenMenu});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'sw_TZ',
    symbol: 'Tsh ',
    decimalDigits: 0,
  );

  String _money(num amount) => _currencyFormat.format(amount);
  String get _businessId => widget.user.businessId ?? 'default_business';

  Stream<QuerySnapshot<Map<String, dynamic>>> get _productsStream {
    return FirebaseFirestore.instance
        .collection('products')
        .orderBy('name')
        .snapshots();
  }

  Stream<Map<String, bool>> get _permissionsStream {
    final businessId = widget.user.businessId ?? 'default_business';
    final roleDocId = '${businessId}_${widget.user.role}';

    return Stream.fromFuture(
          FirebaseFirestore.instance.collection('roles').doc(roleDocId).get(),
        )
        .asyncExpand((initial) {
          if (initial.exists) {
            return FirebaseFirestore.instance
                .collection('roles')
                .doc(roleDocId)
                .snapshots();
          }
          return FirebaseFirestore.instance
              .collection('roles')
              .doc(widget.user.role)
              .snapshots();
        })
        .map((doc) => Map<String, bool>.from(doc.data()?['permissions'] ?? {}));
  }

  bool _can(Map<String, bool> permissions, String featureId) {
    if (widget.user.role == UserRole.superAdmin) return true;
    if (permissions.isEmpty) return true;
    return permissions[featureId] == true;
  }

  void _openAddProductSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddProductSheet(user: widget.user),
    );
  }

  void _openEditProductSheet(Product product, String? imageUrl) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddProductSheet(
        user: widget.user,
        product: product,
        existingImageUrl: imageUrl,
      ),
    );
  }

  Future<void> _deleteProduct(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text(
          '${product.name} will be removed from inventory and the online shop.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FirebaseFirestore.instance
        .collection('products')
        .doc(product.id)
        .delete();
    try {
      await FirebaseStorage.instance
          .ref()
          .child('product_images')
          .child('${product.id}.jpg')
          .delete();
    } catch (_) {
      // Products are allowed to have no uploaded image.
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Product deleted.')));
    }
  }

  void _openPurchaseStockSheet(Product product) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _PurchaseStockSheet(product: product, user: widget.user),
    );
  }

  void _openSupplierManagementSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _InventorySupplierSheet(user: widget.user),
    );
  }

  void _openProductHistory(Product product) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ProductHistorySheet(
        product: product,
        businessId: _businessId,
        money: _money,
      ),
    );
  }

  Product _productFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Product.fromMap({
      ...data,
      'id': (data['id'] as String?)?.isNotEmpty == true ? data['id'] : doc.id,
      'barcode': data['barcode'] ?? '',
      'category': data['category'] ?? 'General',
      'isSynced': 1,
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, bool>>(
      stream: _permissionsStream,
      builder: (context, permissionSnapshot) {
        final permissions = permissionSnapshot.data ?? {};
        final canAddProduct = _can(permissions, 'add_product');
        final canPurchaseStock = _can(permissions, 'purchase_stock');

        return Scaffold(
          appBar: AppBar(
            leading: widget.onOpenMenu == null
                ? null
                : IconButton(
                    tooltip: 'Menu',
                    onPressed: widget.onOpenMenu,
                    icon: const Icon(Icons.menu),
                  ),
            title: const Text('Inventory Management'),
            actions: [
              NotificationBellButton(user: widget.user),
              IconButton(
                tooltip: 'Supplier management',
                icon: const Icon(Icons.local_shipping),
                onPressed: _openSupplierManagementSheet,
              ),
              if (canAddProduct)
                IconButton(
                  tooltip: 'Add product',
                  icon: const Icon(Icons.add),
                  onPressed: _openAddProductSheet,
                ),
            ],
          ),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _productsStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text('Could not load products: ${snapshot.error}'),
                );
              }

              if (!snapshot.hasData) {
                return const Center(child: ModernLoadingIndicator());
              }

              final productDocs = snapshot.data!.docs.where((doc) {
                final data = doc.data();
                return (data['businessId'] as String? ?? 'default_business') ==
                    _businessId;
              }).toList();
              final products = productDocs.map(_productFromDoc).toList();

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('sales')
                    .orderBy('timestamp', descending: true)
                    .limit(300)
                    .snapshots(),
                builder: (context, salesSnapshot) {
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('stock_purchases')
                        .orderBy('createdAt', descending: true)
                        .limit(300)
                        .snapshots(),
                    builder: (context, purchaseSnapshot) {
                      final report = _InventoryReport.fromData(
                        products: products,
                        sales: salesSnapshot.data?.docs ?? const [],
                        purchases: purchaseSnapshot.data?.docs ?? const [],
                        businessId: _businessId,
                      );

                      return Column(
                        children: [
                          _InventoryReportingPanel(
                            report: report,
                            money: _money,
                          ),
                          Expanded(
                            child: products.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No Firebase products yet. Add one to start selling.',
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: products.length,
                                    separatorBuilder: (_, _) =>
                                        const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final product = products[index];
                                      final raw = productDocs[index].data();
                                      final imageUrl =
                                          raw['imageUrl'] as String?;
                                      final isLow = product.stockQuantity < 10;
                                      final expiryText = _expiryText(product);

                                      return ListTile(
                                        leading: _ProductAvatar(
                                          imageUrl: imageUrl,
                                          isLow: isLow,
                                        ),
                                        title: Text(
                                          product.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text(
                                          [
                                            product.category,
                                            'Batch: ${product.batchNumber ?? 'Not set'}',
                                            expiryText,
                                            'Supplier: ${product.supplierName ?? 'Not set'}',
                                          ].join(' | '),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        trailing: SizedBox(
                                          width: canAddProduct ? 264 : 176,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.end,
                                                  children: [
                                                    Text(
                                                      product.stockQuantity
                                                          .toStringAsFixed(0),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: isLow
                                                            ? Theme.of(context)
                                                                  .colorScheme
                                                                  .error
                                                            : null,
                                                      ),
                                                    ),
                                                    Text(
                                                      _money(product.price),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: Theme.of(
                                                        context,
                                                      ).textTheme.bodySmall,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: 'History',
                                                visualDensity:
                                                    VisualDensity.compact,
                                                onPressed: () =>
                                                    _openProductHistory(
                                                      product,
                                                    ),
                                                icon: const Icon(Icons.history),
                                              ),
                                              if (canAddProduct)
                                                IconButton(
                                                  tooltip: 'Edit product',
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  onPressed: () =>
                                                      _openEditProductSheet(
                                                        product,
                                                        imageUrl,
                                                      ),
                                                  icon: const Icon(Icons.edit),
                                                ),
                                              if (canAddProduct)
                                                IconButton(
                                                  tooltip: 'Delete product',
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  onPressed: () =>
                                                      _deleteProduct(product),
                                                  icon: const Icon(
                                                    Icons.delete_outline,
                                                  ),
                                                ),
                                              if (canPurchaseStock)
                                                IconButton(
                                                  tooltip: 'Purchase stock',
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  onPressed: () =>
                                                      _openPurchaseStockSheet(
                                                        product,
                                                      ),
                                                  icon: const Icon(
                                                    Icons.add_shopping_cart,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        onTap: () =>
                                            _openProductHistory(product),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _InventorySummaryCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;

  const _InventorySummaryCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InventoryReportingPanel extends StatelessWidget {
  final _InventoryReport report;
  final String Function(num amount) money;

  const _InventoryReportingPanel({required this.report, required this.money});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1000
              ? 4
              : constraints.maxWidth >= 560
              ? 2
              : 1;
          return GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: columns == 1 ? 4 : 2.2,
            children: [
              _InventorySummaryCard(
                icon: Icons.inventory_2,
                color: Theme.of(context).colorScheme.primary,
                title: 'Stock Value',
                value: money(report.stockValue),
              ),
              _InventorySummaryCard(
                icon: Icons.warning,
                color: Theme.of(context).colorScheme.error,
                title: 'Low Stock',
                value: '${report.lowStockCount} items',
              ),
              _InventorySummaryCard(
                icon: Icons.event_busy,
                color: Colors.orange,
                title: 'Expiring Soon',
                value: '${report.expiringSoonCount} items',
              ),
              _InventorySummaryCard(
                icon: Icons.shopping_bag,
                color: Colors.green,
                title: 'Sold Recently',
                value: report.recentSoldQuantity.toStringAsFixed(0),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InventoryReport {
  final double stockValue;
  final int lowStockCount;
  final int expiringSoonCount;
  final double recentSoldQuantity;

  const _InventoryReport({
    required this.stockValue,
    required this.lowStockCount,
    required this.expiringSoonCount,
    required this.recentSoldQuantity,
  });

  factory _InventoryReport.fromData({
    required List<Product> products,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> sales,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> purchases,
    required String businessId,
  }) {
    final now = DateTime.now();
    final expiringSoon = products.where((product) {
      final expiry = DateTime.tryParse(product.expiryDate ?? '');
      if (expiry == null) return false;
      final days = expiry.difference(now).inDays;
      return days >= 0 && days <= 30;
    }).length;

    var soldQuantity = 0.0;
    for (final doc in sales) {
      final data = doc.data();
      if ((data['businessId'] as String? ?? businessId) != businessId) {
        continue;
      }
      for (final item in _decodeSaleItems(data['itemsJson'])) {
        soldQuantity += item.quantity;
      }
    }

    return _InventoryReport(
      stockValue: products.fold<double>(
        0,
        (total, product) => total + product.stockQuantity * product.productCost,
      ),
      lowStockCount: products
          .where((product) => product.stockQuantity < 10)
          .length,
      expiringSoonCount: expiringSoon,
      recentSoldQuantity: soldQuantity,
    );
  }
}

class _ProductAvatar extends StatelessWidget {
  final String? imageUrl;
  final bool isLow;

  const _ProductAvatar({required this.imageUrl, required this.isLow});

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isLow
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CircleAvatar(backgroundImage: NetworkImage(imageUrl!));
    }

    return CircleAvatar(
      backgroundColor: backgroundColor,
      child: const Icon(Icons.inventory, color: Colors.white),
    );
  }
}

String _expiryText(Product product) {
  final expiry = DateTime.tryParse(product.expiryDate ?? '');
  if (expiry == null) return 'Expiry: Not set';
  final days = expiry.difference(DateTime.now()).inDays;
  if (days < 0) return 'Expired';
  if (days <= 30) return 'Expires in $days days';
  return 'Expiry: ${DateFormat('yyyy-MM-dd').format(expiry)}';
}

class _SaleMovement {
  final String productId;
  final String name;
  final double quantity;
  final double total;

  const _SaleMovement({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.total,
  });
}

List<_SaleMovement> _decodeSaleItems(dynamic itemsJson) {
  if (itemsJson is! String || itemsJson.isEmpty) return const [];
  try {
    final decoded = jsonDecode(itemsJson);
    if (decoded is! List) return const [];
    return decoded.whereType<Map>().map((item) {
      return _SaleMovement(
        productId: item['productId']?.toString() ?? '',
        name: item['name']?.toString() ?? 'Product',
        quantity: (item['quantity'] as num?)?.toDouble() ?? 0,
        total: (item['total'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
  } catch (_) {
    return const [];
  }
}

class _ProductHistorySheet extends StatelessWidget {
  final Product product;
  final String businessId;
  final String Function(num amount) money;

  const _ProductHistorySheet({
    required this.product,
    required this.businessId,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('MMM d, yyyy HH:mm');
    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return ListView(
            controller: controller,
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      product.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text(
                      'Stock ${product.stockQuantity.toStringAsFixed(0)}',
                    ),
                  ),
                  Chip(
                    label: Text('Batch ${product.batchNumber ?? 'Not set'}'),
                  ),
                  Chip(label: Text(_expiryText(product))),
                  Chip(
                    label: Text(
                      'Supplier ${product.supplierName ?? 'Not set'}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Purchase History',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _PurchaseHistoryList(
                product: product,
                businessId: businessId,
                date: date,
              ),
              const SizedBox(height: 18),
              Text(
                'Sales History',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _SalesHistoryList(
                product: product,
                businessId: businessId,
                date: date,
                money: money,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PurchaseHistoryList extends StatelessWidget {
  final Product product;
  final String businessId;
  final DateFormat date;

  const _PurchaseHistoryList({
    required this.product,
    required this.businessId,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('stock_purchases')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        final docs =
            snapshot.data?.docs.where((doc) {
              final data = doc.data();
              return data['productId'] == product.id &&
                  (data['businessId'] as String? ?? businessId) == businessId;
            }).toList() ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        if (docs.isEmpty) {
          return const _HistoryEmpty(message: 'No purchases yet.');
        }
        return Card(
          child: Column(
            children: docs.map((doc) {
              final data = doc.data();
              final quantity = (data['quantity'] as num?)?.toDouble() ?? 0;
              return ListTile(
                dense: true,
                leading: const Icon(Icons.add_shopping_cart),
                title: Text('+${quantity.toStringAsFixed(0)} units'),
                subtitle: Text(
                  [
                    date.format(_date(data['createdAt'])),
                    if (data['batchNumber'] != null)
                      'Batch ${data['batchNumber']}',
                    if (data['expiryDate'] != null) 'Exp ${data['expiryDate']}',
                  ].join(' | '),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _SalesHistoryList extends StatelessWidget {
  final Product product;
  final String businessId;
  final DateFormat date;
  final String Function(num amount) money;

  const _SalesHistoryList({
    required this.product,
    required this.businessId,
    required this.date,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('sales')
          .orderBy('timestamp', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        final rows = <MapEntry<Map<String, dynamic>, _SaleMovement>>[];
        for (final doc in snapshot.data?.docs ?? const []) {
          final data = doc.data();
          if ((data['businessId'] as String? ?? businessId) != businessId) {
            continue;
          }
          for (final item in _decodeSaleItems(data['itemsJson'])) {
            if (item.productId == product.id) {
              rows.add(MapEntry(data, item));
            }
          }
        }
        if (rows.isEmpty) return const _HistoryEmpty(message: 'No sales yet.');
        return Card(
          child: Column(
            children: rows.map((row) {
              final sale = row.key;
              final item = row.value;
              return ListTile(
                dense: true,
                leading: const Icon(Icons.receipt_long),
                title: Text('-${item.quantity.toStringAsFixed(0)} units'),
                subtitle: Text(date.format(_date(sale['timestamp']))),
                trailing: Text(money(item.total)),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _HistoryEmpty extends StatelessWidget {
  final String message;
  const _HistoryEmpty({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
    );
  }
}

class _InventorySupplierSheet extends StatefulWidget {
  final User user;

  const _InventorySupplierSheet({required this.user});

  @override
  State<_InventorySupplierSheet> createState() =>
      _InventorySupplierSheetState();
}

class _InventorySupplierSheetState extends State<_InventorySupplierSheet> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  bool _isSaving = false;

  String get _businessId => widget.user.businessId ?? 'default_business';

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _saveSupplier() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _isSaving = true);
    await FirebaseFirestore.instance.collection('suppliers').add({
      'businessId': _businessId,
      'name': name,
      'phone': _phoneController.text.trim(),
      'address': _addressController.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _nameController.clear();
      _phoneController.clear();
      _addressController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return ListView(
            controller: controller,
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Supplier Management',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Supplier name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _isSaving ? null : _saveSupplier,
                icon: const Icon(Icons.save),
                label: Text(_isSaving ? 'Saving...' : 'Save Supplier'),
              ),
              const SizedBox(height: 20),
              Text('Suppliers', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('suppliers')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  final docs =
                      snapshot.data?.docs.where((doc) {
                        return (doc.data()['businessId'] as String? ??
                                'default_business') ==
                            _businessId;
                      }).toList() ??
                      const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                  if (docs.isEmpty) {
                    return const _HistoryEmpty(message: 'No suppliers yet.');
                  }
                  return Card(
                    child: Column(
                      children: docs.map((doc) {
                        final data = doc.data();
                        return ListTile(
                          leading: const Icon(Icons.local_shipping),
                          title: Text(data['name'] as String? ?? 'Supplier'),
                          subtitle: Text(
                            data['phone'] as String? ?? 'No phone',
                          ),
                        );
                      }).toList(),
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
}

class _AddProductSheet extends StatefulWidget {
  final User user;
  final Product? product;
  final String? existingImageUrl;

  const _AddProductSheet({
    required this.user,
    this.product,
    this.existingImageUrl,
  });

  @override
  State<_AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends State<_AddProductSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _costController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  final _brandController = TextEditingController();
  final _unitController = TextEditingController();
  final _batchController = TextEditingController();
  final _expiryController = TextEditingController();
  final _manufacturingController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _aliasesController = TextEditingController();
  final _shopNameController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  final List<XFile> _images = [];
  String _selectedCategory = 'General';
  String? _selectedPriceGroupId;
  String? _selectedSupplierId;
  String? _selectedSupplierName;
  String? _selectedTaxRuleId;
  String? _selectedBranchId;
  bool _isSaving = false;
  bool _isAvailableOnline = false;
  String? _businessLipaNumber;
  bool _freeShipping = true;
  final _shippingFeeController = TextEditingController(text: '0');
  String _paymentTiming = 'business_default';
  String _paymentAmountPolicy = 'business_default';
  String get _businessId => widget.user.businessId ?? 'default_business';

  @override
  void initState() {
    super.initState();
    _selectedBranchId = widget.user.branchId;
    _unitController.text = 'pcs';
    if (widget.product == null) {
      FirebaseFirestore.instance
          .collection('businesses')
          .doc(_businessId)
          .get()
          .then((doc) {
            final name = doc.data()?['name'] as String?;
            if (mounted) {
              setState(() {
                if (name != null && name.trim().isNotEmpty) {
                  _shopNameController.text = name.trim();
                }
                _businessLipaNumber = doc.data()?['lipaNumber'] as String?;
              });
            }
          });
    }
    final product = widget.product;
    if (product != null) {
      _nameController.text = product.name;
      _barcodeController.text = product.barcode;
      _costController.text = product.productCost.toString();
      _priceController.text = product.price.toString();
      _stockController.text = product.stockQuantity.toString();
      _brandController.text = product.brandName ?? '';
      _unitController.text = product.unitOfMeasurement ?? 'pcs';
      _batchController.text = product.batchNumber ?? '';
      _expiryController.text = product.expiryDate ?? '';
      _manufacturingController.text = product.manufacturingDate ?? '';
      _descriptionController.text = product.description ?? '';
      _aliasesController.text = product.aliases.join(', ');
      _shopNameController.text = product.shopName ?? '';
      _selectedCategory = product.category;
      _selectedPriceGroupId = product.priceGroupId;
      _selectedSupplierId = product.supplierId;
      _selectedSupplierName = product.supplierName;
      _selectedTaxRuleId = product.taxRuleId;
      _selectedBranchId = product.branchId;
      _isAvailableOnline = product.isAvailableOnline;
      _freeShipping = product.freeShipping;
      _shippingFeeController.text = product.shippingFee.toString();
      _paymentTiming = product.paymentTiming;
      _paymentAmountPolicy = product.paymentAmountPolicy;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _barcodeController.dispose();
    _costController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _brandController.dispose();
    _unitController.dispose();
    _batchController.dispose();
    _expiryController.dispose();
    _manufacturingController.dispose();
    _descriptionController.dispose();
    _aliasesController.dispose();
    _shopNameController.dispose();
    _shippingFeeController.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const _InventoryScannerPage()),
    );

    if (code == null || code.isEmpty || !mounted) return;
    setState(() => _barcodeController.text = code);
  }

  Future<void> _pickImage(ImageSource source) async {
    if (source == ImageSource.gallery) {
      final images = await _imagePicker.pickMultiImage(
        imageQuality: 75,
        maxWidth: 1200,
      );
      if (images.isNotEmpty && mounted) setState(() => _images.addAll(images));
      return;
    }
    final image = await _imagePicker.pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 1200,
    );

    if (image == null || !mounted) return;
    setState(() => _images.add(image));
  }

  Future<List<String>> _uploadImages(String productId) async {
    final urls = <String>[];
    for (var index = 0; index < _images.length; index++) {
      final ref = FirebaseStorage.instance
          .ref()
          .child('product_images')
          .child(productId)
          .child('${DateTime.now().microsecondsSinceEpoch}_$index.jpg');
      await ref.putFile(File(_images[index].path));
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final barcode = _barcodeController.text.trim();
      final duplicate = await firestore
          .collection('products')
          .where('barcode', isEqualTo: barcode)
          .limit(1)
          .get();

      if (duplicate.docs.any((doc) => doc.id != widget.product?.id)) {
        throw Exception('A product with this barcode already exists.');
      }

      final productRef = widget.product == null
          ? firestore.collection('products').doc()
          : firestore.collection('products').doc(widget.product!.id);
      final uploadedUrls = await _uploadImages(productRef.id);
      final existingUrls = widget.product?.imageUrls.isNotEmpty == true
          ? widget.product!.imageUrls
          : [if (widget.existingImageUrl != null) widget.existingImageUrl!];
      final imageUrls = [...existingUrls, ...uploadedUrls];
      final imageUrl = imageUrls.isEmpty ? null : imageUrls.first;
      final product = Product(
        id: productRef.id,
        name: _nameController.text.trim(),
        barcode: barcode,
        price: double.parse(_priceController.text.trim()),
        productCost: double.parse(_costController.text.trim()),
        stockQuantity: double.parse(_stockController.text.trim()),
        category: _selectedCategory,
        priceGroupId: _selectedPriceGroupId,
        brandName: _optionalText(_brandController),
        unitOfMeasurement: _optionalText(_unitController),
        supplierId: _selectedSupplierId,
        supplierName: _selectedSupplierName,
        taxRuleId: _selectedTaxRuleId,
        branchId: _selectedBranchId ?? widget.user.branchId,
        businessId: _businessId,
        batchNumber: _optionalText(_batchController),
        expiryDate: _optionalText(_expiryController),
        manufacturingDate: _optionalText(_manufacturingController),
        description: _optionalText(_descriptionController),
        aliases: _aliasesController.text
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(),
        isAvailableOnline: _isAvailableOnline,
        shopName: _optionalText(_shopNameController),
        lipaNumber: _businessLipaNumber ?? widget.product?.lipaNumber,
        imageUrls: imageUrls,
        freeShipping: _freeShipping,
        shippingFee: _freeShipping
            ? 0
            : (double.tryParse(_shippingFeeController.text) ?? 0),
        paymentTiming: _paymentTiming,
        paymentAmountPolicy: _paymentAmountPolicy,
        isSynced: 1,
      );

      await productRef.set({
        ...product.toMap(),
        'aliases': product.aliases,
        'imageUrl': imageUrl,
        if (widget.product == null) 'createdBy': widget.user.id,
        if (widget.product == null) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.product == null ? 'Product added.' : 'Product updated.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save product: $e')));
    }
  }

  String? _requiredText(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    return null;
  }

  String? _requiredNumber(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final number = double.tryParse(value.trim());
    if (number == null || number < 0) return 'Enter a valid number';
    return null;
  }

  String? _optionalText(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      widget.product == null ? 'Add Product' : 'Edit Product',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Product name',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: _requiredText,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _barcodeController,
                  decoration: InputDecoration(
                    labelText: 'Barcode or QR code',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: 'Scan barcode or QR code',
                      onPressed: _isSaving ? null : _scanBarcode,
                      icon: const Icon(Icons.qr_code_scanner),
                    ),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: _requiredText,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _costController,
                        decoration: const InputDecoration(
                          labelText: 'Product cost',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: _requiredNumber,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _priceController,
                        decoration: const InputDecoration(
                          labelText: 'Selling price',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: _requiredNumber,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _stockController,
                        decoration: const InputDecoration(
                          labelText: 'Opening stock',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: _requiredNumber,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _unitController,
                        decoration: const InputDecoration(
                          labelText: 'Unit of measurement',
                          hintText: 'pcs, kg, box',
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _categoryDropdown(),
                const SizedBox(height: 12),
                _priceGroupDropdown(),
                const SizedBox(height: 12),
                _taxDropdown(),
                const SizedBox(height: 12),
                _branchDropdown(),
                const SizedBox(height: 12),
                _supplierDropdown(),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _brandController,
                  decoration: const InputDecoration(
                    labelText: 'Brand name (optional)',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _batchController,
                  decoration: const InputDecoration(
                    labelText: 'Batch number (optional)',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _dateField(
                        controller: _manufacturingController,
                        label: 'Manufacturing date',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _dateField(
                        controller: _expiryController,
                        label: 'Expiry date',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _aliasesController,
                  decoration: const InputDecoration(
                    labelText: 'Search aliases (optional)',
                    hintText: 'mkate, bread loaf, white loaf',
                    helperText:
                        'Separate English and Kiswahili names with commas.',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Product description (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show in online marketplace'),
                  subtitle: const Text(
                    'Customers can discover and purchase this product online.',
                  ),
                  value: _isAvailableOnline,
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _isAvailableOnline = value),
                ),
                if (_isAvailableOnline) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _shopNameController,
                    decoration: const InputDecoration(
                      labelText: 'Business shown to customers',
                      helperText: 'Loaded from Business Settings',
                      border: OutlineInputBorder(),
                    ),
                    validator: _requiredText,
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Free shipping'),
                    value: _freeShipping,
                    onChanged: (value) => setState(() => _freeShipping = value),
                  ),
                  if (!_freeShipping)
                    TextFormField(
                      controller: _shippingFeeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Product shipping fee',
                        prefixText: 'Tsh ',
                      ),
                      validator: _requiredNumber,
                    ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _paymentTiming,
                    decoration: const InputDecoration(
                      labelText: 'Payment timing for this product',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'business_default',
                        child: Text('Use business default'),
                      ),
                      DropdownMenuItem(
                        value: 'before_order',
                        child: Text('Before order'),
                      ),
                      DropdownMenuItem(
                        value: 'on_delivery',
                        child: Text('On delivery'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _paymentTiming = value!),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _paymentAmountPolicy,
                    decoration: const InputDecoration(
                      labelText: 'Payment amount for this product',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'business_default',
                        child: Text('Use business default'),
                      ),
                      DropdownMenuItem(
                        value: 'full',
                        child: Text('Full payment'),
                      ),
                      DropdownMenuItem(
                        value: 'partial',
                        child: Text('Partial payment'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _paymentAmountPolicy = value!),
                  ),
                ],
                const SizedBox(height: 12),
                _imagePickerRow(),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _saveProduct,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: ModernLoadingIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(
                      _isSaving
                          ? 'Saving...'
                          : widget.product == null
                          ? 'Save Product'
                          : 'Save Changes',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _categoryDropdown() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('product_categories')
          .orderBy('name')
          .snapshots(),
      builder: (context, snapshot) {
        final categories =
            snapshot.data?.docs
                .where(
                  (doc) =>
                      (doc.data()['businessId'] as String? ??
                          'default_business') ==
                      _businessId,
                )
                .map((doc) => doc.data()['name'] as String? ?? 'General')
                .where((name) => name.trim().isNotEmpty)
                .toSet()
                .toList() ??
            const <String>[];
        final values = [
          'General',
          ...categories.where((name) => name != 'General'),
        ];
        if (!values.contains(_selectedCategory)) {
          _selectedCategory = values.first;
        }

        return DropdownButtonFormField<String>(
          initialValue: _selectedCategory,
          decoration: const InputDecoration(
            labelText: 'Category',
            border: OutlineInputBorder(),
          ),
          items: values
              .map(
                (category) =>
                    DropdownMenuItem(value: category, child: Text(category)),
              )
              .toList(),
          onChanged: _isSaving
              ? null
              : (value) => setState(() => _selectedCategory = value!),
          validator: _requiredText,
        );
      },
    );
  }

  Widget _priceGroupDropdown() {
    return _optionalDocDropdown(
      collection: 'price_groups',
      label: 'Price group (optional)',
      selectedValue: _selectedPriceGroupId,
      nameBuilder: (data) => data['name'] as String? ?? 'Price group',
      onChanged: (value, data) => setState(() => _selectedPriceGroupId = value),
    );
  }

  Widget _taxDropdown() {
    return _optionalDocDropdown(
      collection: 'tax_rules',
      label: 'Tax rule (optional)',
      selectedValue: _selectedTaxRuleId,
      nameBuilder: (data) {
        final name = data['name'] as String? ?? 'Tax';
        final rate = (data['rate'] as num?)?.toDouble() ?? 0;
        return '$name (${rate.toStringAsFixed(2)}%)';
      },
      onChanged: (value, data) => setState(() => _selectedTaxRuleId = value),
    );
  }

  Widget _branchDropdown() {
    return _optionalDocDropdown(
      collection: 'branches',
      label: 'Business location / branch (optional)',
      selectedValue: _selectedBranchId,
      nameBuilder: (data) => data['name'] as String? ?? 'Branch',
      onChanged: (value, data) => setState(() => _selectedBranchId = value),
    );
  }

  Widget _supplierDropdown() {
    return _optionalDocDropdown(
      collection: 'suppliers',
      label: 'Supplier information (optional)',
      selectedValue: _selectedSupplierId,
      nameBuilder: (data) => data['name'] as String? ?? 'Supplier',
      onChanged: (value, data) {
        setState(() {
          _selectedSupplierId = value;
          _selectedSupplierName = data?['name'] as String?;
        });
      },
    );
  }

  Widget _optionalDocDropdown({
    required String collection,
    required String label,
    required String? selectedValue,
    required String Function(Map<String, dynamic> data) nameBuilder,
    required void Function(String? value, Map<String, dynamic>? data) onChanged,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection(collection).snapshots(),
      builder: (context, snapshot) {
        final docs =
            snapshot.data?.docs
                .where(
                  (doc) =>
                      (doc.data()['businessId'] as String? ??
                          'default_business') ==
                      _businessId,
                )
                .toList() ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final hasSelected =
            selectedValue == null || docs.any((doc) => doc.id == selectedValue);

        return DropdownButtonFormField<String?>(
          initialValue: hasSelected ? selectedValue : null,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('None')),
            ...docs.map((doc) {
              return DropdownMenuItem<String?>(
                value: doc.id,
                child: Text(nameBuilder(doc.data())),
              );
            }),
          ],
          onChanged: _isSaving
              ? null
              : (value) {
                  final data = docs
                      .where((doc) => doc.id == value)
                      .map((doc) => doc.data())
                      .cast<Map<String, dynamic>?>()
                      .firstOrNull;
                  onChanged(value, data);
                },
        );
      },
    );
  }

  Widget _dateField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: '$label (optional)',
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: 'Pick date',
          onPressed: _isSaving ? null : () => _pickDate(controller),
          icon: const Icon(Icons.calendar_month),
        ),
      ),
    );
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 30),
      lastDate: DateTime(now.year + 30),
      initialDate: DateTime.tryParse(controller.text) ?? now,
    );
    if (picked == null || !mounted) return;
    controller.text = DateFormat('yyyy-MM-dd').format(picked);
  }

  Widget _imagePickerRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Product images (optional)'),
        const SizedBox(height: 8),
        if (_images.isNotEmpty)
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _images.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_images[index].path),
                      width: 92,
                      height: 92,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: IconButton.filled(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Remove image',
                      onPressed: _isSaving
                          ? null
                          : () => setState(() => _images.removeAt(index)),
                      icon: const Icon(Icons.close, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _isSaving
                  ? null
                  : () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.add_a_photo),
              label: const Text('Take photo'),
            ),
            OutlinedButton.icon(
              onPressed: _isSaving
                  ? null
                  : () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library),
              label: const Text('Choose multiple'),
            ),
          ],
        ),
      ],
    );
  }
}

class _PurchaseStockSheet extends StatefulWidget {
  final Product product;
  final User user;

  const _PurchaseStockSheet({required this.product, required this.user});

  @override
  State<_PurchaseStockSheet> createState() => _PurchaseStockSheetState();
}

class _PurchaseStockSheetState extends State<_PurchaseStockSheet> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _newPriceController = TextEditingController();
  final _batchController = TextEditingController();
  final _expiryController = TextEditingController();
  bool _isSaving = false;
  bool _updateSellingPrice = false;

  @override
  void initState() {
    super.initState();
    _newPriceController.text = widget.product.price.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _newPriceController.dispose();
    _batchController.dispose();
    _expiryController.dispose();
    super.dispose();
  }

  String? _requiredPositiveNumber(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final number = double.tryParse(value.trim());
    if (number == null || number <= 0) return 'Enter a number above 0';
    return null;
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 30),
      initialDate: DateTime.tryParse(_expiryController.text) ?? now,
    );
    if (picked == null || !mounted) return;
    _expiryController.text = DateFormat('yyyy-MM-dd').format(picked);
  }

  Future<void> _savePurchase() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final productRef = firestore
          .collection('products')
          .doc(widget.product.id);
      final purchaseRef = firestore.collection('stock_purchases').doc();
      final quantity = double.parse(_quantityController.text.trim());
      final newPrice = double.parse(_newPriceController.text.trim());
      final batchNumber = _batchController.text.trim();
      final expiryDate = _expiryController.text.trim();

      await firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(productRef);
        if (!snapshot.exists) {
          throw Exception('Product no longer exists.');
        }

        final data = snapshot.data() ?? {};
        final currentStock = (data['stockQuantity'] as num?)?.toDouble() ?? 0;
        final currentPrice =
            (data['price'] as num?)?.toDouble() ?? widget.product.price;

        transaction.update(productRef, {
          'businessId': widget.user.businessId ?? 'default_business',
          'stockQuantity': currentStock + quantity,
          'price': _updateSellingPrice ? newPrice : currentPrice,
          if (batchNumber.isNotEmpty) 'batchNumber': batchNumber,
          if (expiryDate.isNotEmpty) 'expiryDate': expiryDate,
          'updatedAt': FieldValue.serverTimestamp(),
          'lastPurchasedAt': FieldValue.serverTimestamp(),
          'lastPurchasedQuantity': quantity,
          'lastPurchasedBy': widget.user.id,
        });

        transaction.set(purchaseRef, {
          'id': purchaseRef.id,
          'productId': widget.product.id,
          'productName': data['name'] ?? widget.product.name,
          'barcode': data['barcode'] ?? widget.product.barcode,
          'businessId': widget.user.businessId ?? 'default_business',
          'quantity': quantity,
          'previousStock': currentStock,
          'newStock': currentStock + quantity,
          'previousPrice': currentPrice,
          'newPrice': _updateSellingPrice ? newPrice : currentPrice,
          'batchNumber': batchNumber.isEmpty ? null : batchNumber,
          'expiryDate': expiryDate.isEmpty ? null : expiryDate,
          'purchasedBy': widget.user.id,
          'branchId': widget.user.branchId ?? 'main',
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${widget.product.name} stock increased by ${quantity.toStringAsFixed(0)}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not purchase stock: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Purchase Stock',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Icon(Icons.inventory_2)),
                  title: Text(widget.product.name),
                  subtitle: Text(
                    'Current stock: ${widget.product.stockQuantity.toStringAsFixed(0)}',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _quantityController,
                  decoration: const InputDecoration(
                    labelText: 'Quantity purchased',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _requiredPositiveNumber,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _batchController,
                        decoration: const InputDecoration(
                          labelText: 'Batch number',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _expiryController,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Expiry date',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: 'Pick expiry date',
                            onPressed: _isSaving ? null : _pickExpiryDate,
                            icon: const Icon(Icons.calendar_month),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Update selling price'),
                  value: _updateSellingPrice,
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _updateSellingPrice = value),
                ),
                if (_updateSellingPrice) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _newPriceController,
                    decoration: const InputDecoration(
                      labelText: 'New selling price',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: _requiredPositiveNumber,
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _savePurchase,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: ModernLoadingIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_shopping_cart),
                    label: Text(_isSaving ? 'Saving...' : 'Add Stock'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InventoryScannerPage extends StatefulWidget {
  const _InventoryScannerPage();

  @override
  State<_InventoryScannerPage> createState() => _InventoryScannerPageState();
}

class _InventoryScannerPageState extends State<_InventoryScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue?.trim();
      if (code == null || code.isEmpty) continue;

      _hasScanned = true;
      Navigator.pop(context, code);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Product Code'),
        actions: [
          IconButton(
            tooltip: 'Toggle torch',
            onPressed: _controller.toggleTorch,
            icon: const Icon(Icons.flash_on),
          ),
          IconButton(
            tooltip: 'Switch camera',
            onPressed: _controller.switchCamera,
            icon: const Icon(Icons.cameraswitch),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 260,
              height: 180,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.black.withValues(alpha: 0.65),
              child: const SafeArea(
                top: false,
                child: Text(
                  'Scan the product barcode or QR code to fill the product code field.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

DateTime _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models.dart';

class DashboardScreen extends StatelessWidget {
  final User user;
  final VoidCallback? onOpenMenu;
  const DashboardScreen({super.key, required this.user, this.onOpenMenu});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: onOpenMenu == null
            ? null
            : IconButton(
                tooltip: 'Menu',
                onPressed: onOpenMenu,
                icon: const Icon(Icons.menu),
              ),
        title: const Text('Dashboard'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('products').snapshots(),
        builder: (context, productSnapshot) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('sales')
                .orderBy('timestamp', descending: true)
                .limit(50)
                .snapshots(),
            builder: (context, salesSnapshot) {
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('stock_purchases')
                    .orderBy('createdAt', descending: true)
                    .limit(20)
                    .snapshots(),
                builder: (context, purchaseSnapshot) {
                  if (productSnapshot.hasError ||
                      salesSnapshot.hasError ||
                      purchaseSnapshot.hasError) {
                    return Center(
                      child: Text(
                        'Could not load dashboard data from Firebase.',
                      ),
                    );
                  }

                  if (!productSnapshot.hasData ||
                      !salesSnapshot.hasData ||
                      !purchaseSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final data = _DashboardData.fromSnapshots(
                    productSnapshot.data!.docs,
                    salesSnapshot.data!.docs,
                    purchaseSnapshot.data!.docs,
                    user.businessId ?? 'default_business',
                  );

                  return _DashboardContent(user: user, data: data);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  final User user;
  final _DashboardData data;

  const _DashboardContent({required this.user, required this.data});

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(
      locale: 'sw_TZ',
      symbol: 'Tsh ',
      decimalDigits: 0,
    );
    final dateFormat = DateFormat('MMM d, HH:mm');

    return RefreshIndicator(
      onRefresh: () async {
        await FirebaseFirestore.instance.disableNetwork();
        await FirebaseFirestore.instance.enableNetwork();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome, ${user.name}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Live overview from Firebase',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 900
                    ? 4
                    : constraints.maxWidth >= 560
                    ? 2
                    : 1;

                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: columns == 1 ? 3.2 : 2.1,
                  children: [
                    _StatCard(
                      title: 'Sales Total',
                      value: currencyFormat.format(data.salesTotal),
                      icon: Icons.payments,
                      color: Colors.green,
                    ),
                    _StatCard(
                      title: 'Sales Count',
                      value: data.salesCount.toString(),
                      icon: Icons.receipt_long,
                      color: Colors.blue,
                    ),
                    _StatCard(
                      title: 'Products',
                      value: data.productCount.toString(),
                      icon: Icons.inventory_2,
                      color: Colors.indigo,
                    ),
                    _StatCard(
                      title: 'Low Stock',
                      value: data.lowStockCount.toString(),
                      icon: Icons.warning,
                      color: Colors.red,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            _SectionHeader(
              title: 'Recent Sales',
              trailing: '${data.recentSales.length} latest',
            ),
            const SizedBox(height: 8),
            _RecentSalesCard(
              sales: data.recentSales,
              currencyFormat: currencyFormat,
              dateFormat: dateFormat,
            ),
            const SizedBox(height: 20),
            _SectionHeader(
              title: 'Stock Watch',
              trailing: '${data.lowStockProducts.length} low',
            ),
            const SizedBox(height: 8),
            _LowStockCard(products: data.lowStockProducts),
            const SizedBox(height: 20),
            _SectionHeader(
              title: 'Recent Purchases',
              trailing: '${data.recentPurchases.length} latest',
            ),
            const SizedBox(height: 8),
            _PurchaseCard(
              purchases: data.recentPurchases,
              dateFormat: dateFormat,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
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

class _SectionHeader extends StatelessWidget {
  final String title;
  final String trailing;

  const _SectionHeader({required this.title, required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const Spacer(),
        Text(
          trailing,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _RecentSalesCard extends StatelessWidget {
  final List<_SaleSummary> sales;
  final NumberFormat currencyFormat;
  final DateFormat dateFormat;

  const _RecentSalesCard({
    required this.sales,
    required this.currencyFormat,
    required this.dateFormat,
  });

  @override
  Widget build(BuildContext context) {
    if (sales.isEmpty) {
      return const _EmptyCard(message: 'No Firebase sales yet.');
    }

    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: sales.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final sale = sales[index];
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
            title: Text(
              sale.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${sale.paymentMethod} | ${dateFormat.format(sale.date)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              currencyFormat.format(sale.total),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        },
      ),
    );
  }
}

class _LowStockCard extends StatelessWidget {
  final List<Product> products;

  const _LowStockCard({required this.products});

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const _EmptyCard(message: 'No low stock products.');
    }

    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: products.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final product = products[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.error,
              child: const Icon(Icons.warning, color: Colors.white),
            ),
            title: Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              product.category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              product.stockQuantity.toStringAsFixed(0),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PurchaseCard extends StatelessWidget {
  final List<_PurchaseSummary> purchases;
  final DateFormat dateFormat;

  const _PurchaseCard({required this.purchases, required this.dateFormat});

  @override
  Widget build(BuildContext context) {
    if (purchases.isEmpty) {
      return const _EmptyCard(message: 'No stock purchases yet.');
    }

    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: purchases.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final purchase = purchases[index];
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.add_shopping_cart)),
            title: Text(
              purchase.productName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              dateFormat.format(purchase.date),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              '+${purchase.quantity.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String message;

  const _EmptyCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SizedBox(height: 88, child: Center(child: Text(message))),
    );
  }
}

class _DashboardData {
  final int productCount;
  final int lowStockCount;
  final int salesCount;
  final double salesTotal;
  final List<Product> lowStockProducts;
  final List<_SaleSummary> recentSales;
  final List<_PurchaseSummary> recentPurchases;

  const _DashboardData({
    required this.productCount,
    required this.lowStockCount,
    required this.salesCount,
    required this.salesTotal,
    required this.lowStockProducts,
    required this.recentSales,
    required this.recentPurchases,
  });

  factory _DashboardData.fromSnapshots(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> productDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> saleDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> purchaseDocs,
    String businessId,
  ) {
    final scopedProductDocs = productDocs.where((doc) {
      final data = doc.data();
      return (data['businessId'] as String? ?? 'default_business') ==
          businessId;
    });
    final scopedSaleDocs = saleDocs.where((doc) {
      final data = doc.data();
      return (data['businessId'] as String? ?? 'default_business') ==
          businessId;
    }).toList();
    final scopedPurchaseDocs = purchaseDocs.where((doc) {
      final data = doc.data();
      return (data['businessId'] as String? ?? 'default_business') ==
          businessId;
    }).toList();

    final products = scopedProductDocs.map((doc) {
      final data = doc.data();
      return Product.fromMap({
        ...data,
        'id': (data['id'] as String?)?.isNotEmpty == true ? data['id'] : doc.id,
        'barcode': data['barcode'] ?? '',
        'category': data['category'] ?? 'General',
        'isSynced': 1,
      });
    }).toList();

    final lowStockProducts =
        products.where((product) => product.stockQuantity < 10).toList()
          ..sort((a, b) => a.stockQuantity.compareTo(b.stockQuantity));

    final recentSales = scopedSaleDocs.map(_SaleSummary.fromDoc).toList();
    final salesTotal = recentSales.fold<double>(
      0,
      (total, sale) => total + sale.total,
    );

    return _DashboardData(
      productCount: products.length,
      lowStockCount: lowStockProducts.length,
      salesCount: scopedSaleDocs.length,
      salesTotal: salesTotal,
      lowStockProducts: lowStockProducts.take(6).toList(),
      recentSales: recentSales.take(6).toList(),
      recentPurchases: scopedPurchaseDocs
          .map(_PurchaseSummary.fromDoc)
          .take(6)
          .toList(),
    );
  }
}

class _SaleSummary {
  final String id;
  final String title;
  final double total;
  final String paymentMethod;
  final DateTime date;

  const _SaleSummary({
    required this.id,
    required this.title,
    required this.total,
    required this.paymentMethod,
    required this.date,
  });

  factory _SaleSummary.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final items = _decodeSaleItems(data['itemsJson']);
    final title = items.isEmpty ? 'Sale ${doc.id}' : items.join(', ');

    return _SaleSummary(
      id: doc.id,
      title: title,
      total: (data['totalAmount'] as num?)?.toDouble() ?? 0,
      paymentMethod: data['paymentMethod'] as String? ?? 'Unknown',
      date: _dateFromValue(data['timestamp']),
    );
  }

  static List<String> _decodeSaleItems(dynamic value) {
    if (value is! String || value.isEmpty) return [];

    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return [];

      return decoded
          .map((item) {
            if (item is! Map) return null;
            final name = item['name'];
            final quantity = item['quantity'];
            if (name == null) return null;
            return '${quantity ?? 1}x $name';
          })
          .whereType<String>()
          .take(2)
          .toList();
    } catch (_) {
      return [];
    }
  }
}

class _PurchaseSummary {
  final String productName;
  final double quantity;
  final DateTime date;

  const _PurchaseSummary({
    required this.productName,
    required this.quantity,
    required this.date,
  });

  factory _PurchaseSummary.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return _PurchaseSummary(
      productName: data['productName'] as String? ?? 'Unknown product',
      quantity: (data['quantity'] as num?)?.toDouble() ?? 0,
      date: _dateFromValue(data['createdAt']),
    );
  }
}

DateTime _dateFromValue(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'app_loading_indicator.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'models.dart';
import 'notification_inbox_page.dart';

class ReportsScreen extends StatefulWidget {
  final User user;
  final VoidCallback? onOpenMenu;

  const ReportsScreen({super.key, required this.user, this.onOpenMenu});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTimeRange? _dateRange;

  String get _businessId => widget.user.businessId ?? 'default_business';

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange:
          _dateRange ??
          DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
    );

    if (picked != null) setState(() => _dateRange = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.onOpenMenu == null
            ? null
            : IconButton(
                tooltip: 'Menu',
                onPressed: widget.onOpenMenu,
                icon: const Icon(Icons.menu),
              ),
        title: const Text('Reports'),
        actions: [NotificationBellButton(user: widget.user)],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('sales')
            .orderBy('timestamp', descending: true)
            .limit(500)
            .snapshots(),
        builder: (context, salesSnapshot) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('products')
                .orderBy('name')
                .snapshots(),
            builder: (context, productSnapshot) {
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('stock_purchases')
                    .orderBy('createdAt', descending: true)
                    .limit(300)
                    .snapshots(),
                builder: (context, purchaseSnapshot) {
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('expenses')
                        .orderBy('createdAt', descending: true)
                        .limit(300)
                        .snapshots(),
                    builder: (context, expenseSnapshot) {
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('customer_orders')
                            .snapshots(),
                        builder: (context, onlineSnapshot) {
                          if (salesSnapshot.hasError ||
                              productSnapshot.hasError ||
                              purchaseSnapshot.hasError ||
                              expenseSnapshot.hasError ||
                              onlineSnapshot.hasError) {
                            return const Center(
                              child: Text(
                                'Could not load Firebase report data.',
                              ),
                            );
                          }

                          if (!salesSnapshot.hasData ||
                              !productSnapshot.hasData ||
                              !purchaseSnapshot.hasData ||
                              !expenseSnapshot.hasData ||
                              !onlineSnapshot.hasData) {
                            return const Center(
                              child: ModernLoadingIndicator(),
                            );
                          }

                          final report = _ReportData.fromSnapshots(
                            businessId: _businessId,
                            dateRange: _dateRange,
                            sales: salesSnapshot.data!.docs,
                            products: productSnapshot.data!.docs,
                            purchases: purchaseSnapshot.data!.docs,
                            expenses: expenseSnapshot.data!.docs,
                            onlineOrders: onlineSnapshot.data!.docs,
                          );

                          return _ReportsContent(
                            report: report,
                            dateRange: _dateRange,
                            onPickDateRange: _pickDateRange,
                            onClearDateRange: _dateRange == null
                                ? null
                                : () => setState(() => _dateRange = null),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _ReportsContent extends StatelessWidget {
  final _ReportData report;
  final DateTimeRange? dateRange;
  final VoidCallback onPickDateRange;
  final VoidCallback? onClearDateRange;

  const _ReportsContent({
    required this.report,
    required this.dateRange,
    required this.onPickDateRange,
    required this.onClearDateRange,
  });

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'sw_TZ',
      symbol: 'Tsh ',
      decimalDigits: 0,
    );
    final date = DateFormat('MMM d, HH:mm');
    final rangeText = _rangeText(dateRange);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DateFilterCard(
            rangeText: rangeText,
            onPickDateRange: onPickDateRange,
            onClearDateRange: onClearDateRange,
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
                  _MetricCard(
                    title: 'Sales Revenue',
                    value: money.format(report.salesTotal),
                    icon: Icons.payments,
                    color: Colors.green,
                    onPrint: () =>
                        _printSalesRevenue(context, report, money, date),
                  ),
                  _MetricCard(
                    title: 'POS Revenue',
                    value: money.format(report.posSalesTotal),
                    icon: Icons.point_of_sale,
                    color: Colors.blue,
                    onPrint: () => _printFinancial(context, report, money),
                  ),
                  _MetricCard(
                    title: 'Online Revenue',
                    value: money.format(report.onlineSalesTotal),
                    icon: Icons.shopping_bag,
                    color: Colors.purple,
                    onPrint: () => _printFinancial(context, report, money),
                  ),
                  _MetricCard(
                    title: 'Transactions',
                    value: report.salesCount.toString(),
                    icon: Icons.receipt_long,
                    color: Colors.blue,
                    onPrint: () =>
                        _printSalesTransactions(context, report, money, date),
                  ),
                  _MetricCard(
                    title: 'Items Sold',
                    value: report.itemsSold.toStringAsFixed(0),
                    icon: Icons.shopping_bag,
                    color: Colors.indigo,
                    onPrint: () => _printTopProducts(context, report),
                  ),
                  _MetricCard(
                    title: 'Stock Purchased',
                    value: report.stockPurchased.toStringAsFixed(0),
                    icon: Icons.add_shopping_cart,
                    color: Colors.orange,
                    onPrint: () => _printPurchases(context, report, date),
                  ),
                  _MetricCard(
                    title: 'Gross Profit',
                    value: money.format(report.grossProfit),
                    icon: Icons.trending_up,
                    color: Colors.teal,
                    onPrint: () => _printFinancial(context, report, money),
                  ),
                  _MetricCard(
                    title: 'Expenses',
                    value: money.format(report.expensesTotal),
                    icon: Icons.payments,
                    color: Colors.red,
                    onPrint: () => _printFinancial(context, report, money),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          _SectionHeader(
            title: 'Financial Account',
            onPrint: () => _printFinancial(context, report, money),
          ),
          _SimpleBreakdownCard(
            rows: [
              _BreakdownRow('Sales revenue', money.format(report.salesTotal)),
              _BreakdownRow('POS revenue', money.format(report.posSalesTotal)),
              _BreakdownRow(
                'Online revenue',
                money.format(report.onlineSalesTotal),
              ),
              _BreakdownRow(
                'Discounts given',
                money.format(report.discountsTotal),
              ),
              _BreakdownRow('Tax collected', money.format(report.taxTotal)),
              _BreakdownRow('Expenses', money.format(report.expensesTotal)),
              _BreakdownRow(
                'Profit and loss',
                money.format(report.grossProfit),
              ),
            ],
            emptyMessage: 'No financial data for this date range.',
          ),
          const SizedBox(height: 20),
          _SectionHeader(
            title: 'Payment Methods',
            onPrint: () => _printBreakdown(
              context: context,
              title: 'Payment Method Report',
              rangeText: rangeText,
              headers: const ['Payment Method', 'Amount'],
              rows: report.paymentTotals.entries
                  .map((entry) => [entry.key, money.format(entry.value)])
                  .toList(),
            ),
          ),
          _SimpleBreakdownCard(
            rows: report.paymentTotals.entries
                .map(
                  (entry) =>
                      _BreakdownRow(entry.key, money.format(entry.value)),
                )
                .toList(),
            emptyMessage: 'No payment data for this date range.',
          ),
          const SizedBox(height: 20),
          _SectionHeader(
            title: 'Top Selling Products',
            onPrint: () => _printTopProducts(context, report),
          ),
          _SimpleBreakdownCard(
            rows: report.topProducts
                .map(
                  (product) => _BreakdownRow(
                    product.name,
                    '${product.quantity.toStringAsFixed(0)} sold',
                  ),
                )
                .toList(),
            emptyMessage: 'No sold products for this date range.',
          ),
          const SizedBox(height: 20),
          _SectionHeader(
            title: 'Low Stock',
            onPrint: () => _printLowStock(context, report),
          ),
          _SimpleBreakdownCard(
            rows: report.lowStockProducts
                .map(
                  (product) => _BreakdownRow(
                    product.name,
                    '${product.stockQuantity.toStringAsFixed(0)} left',
                  ),
                )
                .toList(),
            emptyMessage: 'No low stock products.',
          ),
          const SizedBox(height: 20),
          _SectionHeader(
            title: 'Recent Stock Purchases',
            onPrint: () => _printPurchases(context, report, date),
          ),
          _SimpleBreakdownCard(
            rows: report.recentPurchases
                .map(
                  (purchase) => _BreakdownRow(
                    purchase.productName,
                    '+${purchase.quantity.toStringAsFixed(0)} | ${date.format(purchase.date)}',
                  ),
                )
                .toList(),
            emptyMessage: 'No stock purchases for this date range.',
          ),
        ],
      ),
    );
  }

  String _rangeText(DateTimeRange? range) {
    if (range == null) return 'All dates';
    final format = DateFormat('MMM d, yyyy');
    return '${format.format(range.start)} - ${format.format(range.end)}';
  }

  Future<void> _printSalesRevenue(
    BuildContext context,
    _ReportData report,
    NumberFormat money,
    DateFormat date,
  ) {
    return _printBreakdown(
      context: context,
      title: 'Sales Revenue Report',
      rangeText: _rangeText(dateRange),
      headers: const ['Date', 'Sale', 'Payment', 'Amount'],
      rows: report.sales
          .map(
            (sale) => [
              date.format(sale.date),
              sale.title,
              sale.paymentMethod,
              money.format(sale.total),
            ],
          )
          .toList(),
      summary: 'Total Revenue: ${money.format(report.salesTotal)}',
    );
  }

  Future<void> _printSalesTransactions(
    BuildContext context,
    _ReportData report,
    NumberFormat money,
    DateFormat date,
  ) {
    return _printBreakdown(
      context: context,
      title: 'Sales Transactions Report',
      rangeText: _rangeText(dateRange),
      headers: const ['Date', 'Sale', 'Payment', 'Amount'],
      rows: report.sales
          .map(
            (sale) => [
              date.format(sale.date),
              sale.title,
              sale.paymentMethod,
              money.format(sale.total),
            ],
          )
          .toList(),
      summary: 'Transactions: ${report.salesCount}',
    );
  }

  Future<void> _printTopProducts(BuildContext context, _ReportData report) {
    return _printBreakdown(
      context: context,
      title: 'Top Selling Products Report',
      rangeText: _rangeText(dateRange),
      headers: const ['Product', 'Quantity Sold'],
      rows: report.topProducts
          .map((product) => [product.name, product.quantity.toStringAsFixed(0)])
          .toList(),
      summary: 'Items Sold: ${report.itemsSold.toStringAsFixed(0)}',
    );
  }

  Future<void> _printLowStock(BuildContext context, _ReportData report) {
    return _printBreakdown(
      context: context,
      title: 'Low Stock Report',
      rangeText: 'Current stock',
      headers: const ['Product', 'Quantity Left'],
      rows: report.lowStockProducts
          .map(
            (product) => [
              product.name,
              product.stockQuantity.toStringAsFixed(0),
            ],
          )
          .toList(),
    );
  }

  Future<void> _printPurchases(
    BuildContext context,
    _ReportData report,
    DateFormat date,
  ) {
    return _printBreakdown(
      context: context,
      title: 'Stock Purchases Report',
      rangeText: _rangeText(dateRange),
      headers: const ['Date', 'Product', 'Quantity'],
      rows: report.recentPurchases
          .map(
            (purchase) => [
              date.format(purchase.date),
              purchase.productName,
              purchase.quantity.toStringAsFixed(0),
            ],
          )
          .toList(),
      summary: 'Stock Purchased: ${report.stockPurchased.toStringAsFixed(0)}',
    );
  }

  Future<void> _printFinancial(
    BuildContext context,
    _ReportData report,
    NumberFormat money,
  ) {
    return _printBreakdown(
      context: context,
      title: 'Profit and Loss Report',
      rangeText: _rangeText(dateRange),
      headers: const ['Account', 'Amount'],
      rows: [
        ['Sales revenue', money.format(report.salesTotal)],
        ['POS revenue', money.format(report.posSalesTotal)],
        ['Online revenue', money.format(report.onlineSalesTotal)],
        ['Discounts given', money.format(report.discountsTotal)],
        ['Tax collected', money.format(report.taxTotal)],
        ['Expenses', money.format(report.expensesTotal)],
        ['Profit and loss', money.format(report.grossProfit)],
      ],
    );
  }

  Future<void> _printBreakdown({
    required BuildContext context,
    required String title,
    required String rangeText,
    required List<String> headers,
    required List<List<String>> rows,
    String? summary,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Date range: $rangeText'),
          if (summary != null) ...[
            pw.SizedBox(height: 8),
            pw.Text(
              summary,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ],
          pw.SizedBox(height: 16),
          if (rows.isEmpty)
            pw.Text('No data available.')
          else
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: rows,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
            ),
        ],
      ),
    );

    try {
      await Printing.layoutPdf(
        name: '$title.pdf',
        onLayout: (_) async => doc.save(),
      );
    } on MissingPluginException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Printing plugin is not registered. Stop the app completely and rebuild it.',
          ),
        ),
      );
    }
  }
}

class _DateFilterCard extends StatelessWidget {
  final String rangeText;
  final VoidCallback onPickDateRange;
  final VoidCallback? onClearDateRange;

  const _DateFilterCard({
    required this.rangeText,
    required this.onPickDateRange,
    required this.onClearDateRange,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.date_range),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                rangeText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              tooltip: 'Choose date range',
              onPressed: onPickDateRange,
              icon: const Icon(Icons.tune),
            ),
            if (onClearDateRange != null)
              IconButton(
                tooltip: 'Clear date range',
                onPressed: onClearDateRange,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onPrint;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.onPrint,
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
            IconButton(
              tooltip: 'Print PDF',
              onPressed: onPrint,
              icon: const Icon(Icons.picture_as_pdf),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onPrint;

  const _SectionHeader({required this.title, required this.onPrint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          IconButton(
            tooltip: 'Print PDF',
            onPressed: onPrint,
            icon: const Icon(Icons.picture_as_pdf),
          ),
        ],
      ),
    );
  }
}

class _SimpleBreakdownCard extends StatelessWidget {
  final List<_BreakdownRow> rows;
  final String emptyMessage;

  const _SimpleBreakdownCard({required this.rows, required this.emptyMessage});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Card(
        child: SizedBox(height: 84, child: Center(child: Text(emptyMessage))),
      );
    }

    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final row = rows[index];
          return ListTile(
            title: Text(
              row.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              row.value,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        },
      ),
    );
  }
}

class _BreakdownRow {
  final String label;
  final String value;

  const _BreakdownRow(this.label, this.value);
}

class _ReportData {
  final int salesCount;
  final double salesTotal;
  final double posSalesTotal;
  final double onlineSalesTotal;
  final double itemsSold;
  final double stockPurchased;
  final double expensesTotal;
  final double discountsTotal;
  final double taxTotal;
  final double grossProfit;
  final List<_SaleRecord> sales;
  final Map<String, double> paymentTotals;
  final List<_ProductSales> topProducts;
  final List<_ReportProduct> lowStockProducts;
  final List<_PurchaseSummary> recentPurchases;

  const _ReportData({
    required this.salesCount,
    required this.salesTotal,
    required this.posSalesTotal,
    required this.onlineSalesTotal,
    required this.itemsSold,
    required this.stockPurchased,
    required this.expensesTotal,
    required this.discountsTotal,
    required this.taxTotal,
    required this.grossProfit,
    required this.sales,
    required this.paymentTotals,
    required this.topProducts,
    required this.lowStockProducts,
    required this.recentPurchases,
  });

  factory _ReportData.fromSnapshots({
    required String businessId,
    required DateTimeRange? dateRange,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> sales,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> products,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> purchases,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> expenses,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> onlineOrders,
  }) {
    bool inRange(DateTime date) {
      if (dateRange == null) return true;
      final start = DateTime(
        dateRange.start.year,
        dateRange.start.month,
        dateRange.start.day,
      );
      final end = DateTime(
        dateRange.end.year,
        dateRange.end.month,
        dateRange.end.day,
        23,
        59,
        59,
        999,
      );
      return !date.isBefore(start) && !date.isAfter(end);
    }

    final scopedSales = sales.map(_SaleRecord.fromDoc).where((sale) {
      return sale.businessId == businessId && inRange(sale.date);
    }).toList();
    final scopedProducts = products.where((doc) {
      final data = doc.data();
      return (data['businessId'] as String? ?? 'default_business') ==
          businessId;
    }).toList();
    final scopedPurchases = purchases.map(_PurchaseSummary.fromDoc).where((
      purchase,
    ) {
      return purchase.businessId == businessId && inRange(purchase.date);
    }).toList();
    final scopedExpenses = expenses.where((doc) {
      final data = doc.data();
      final expenseBusinessId =
          data['businessId'] as String? ?? 'default_business';
      return expenseBusinessId == businessId &&
          inRange(_dateFromValue(data['createdAt']));
    }).toList();
    final scopedOnlineOrders = onlineOrders.where((doc) {
      final data = doc.data();
      final shopIds = (data['shopIds'] as List? ?? const []).map(
        (value) => value.toString(),
      );
      return shopIds.contains(businessId) &&
          data['status'] != 'cancelled' &&
          inRange(_dateFromValue(data['createdAt']));
    }).toList();

    final paymentTotals = <String, double>{};
    final productQuantities = <String, double>{};
    var posSalesTotal = 0.0;
    var onlineSalesTotal = 0.0;
    var itemsSold = 0.0;
    var discountsTotal = 0.0;
    var taxTotal = 0.0;

    for (final sale in scopedSales) {
      posSalesTotal += sale.total;
      discountsTotal += sale.discount;
      taxTotal += sale.tax;
      paymentTotals[sale.paymentMethod] =
          (paymentTotals[sale.paymentMethod] ?? 0) + sale.total;

      for (final item in sale.items) {
        itemsSold += item.quantity;
        productQuantities[item.name] =
            (productQuantities[item.name] ?? 0) + item.quantity;
      }
    }
    for (final order in scopedOnlineOrders) {
      final data = order.data();
      onlineSalesTotal += (data['total'] as num?)?.toDouble() ?? 0;
      for (final item in (data['items'] as List? ?? const [])) {
        if (item is! Map) continue;
        final name = item['name']?.toString() ?? 'Product';
        final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
        itemsSold += quantity;
        productQuantities[name] = (productQuantities[name] ?? 0) + quantity;
      }
    }
    final salesTotal = posSalesTotal + onlineSalesTotal;
    if (onlineSalesTotal > 0) paymentTotals['Online'] = onlineSalesTotal;

    final topProducts =
        productQuantities.entries
            .map((entry) => _ProductSales(entry.key, entry.value))
            .toList()
          ..sort((a, b) => b.quantity.compareTo(a.quantity));

    final lowStockProducts =
        scopedProducts
            .map((doc) {
              final data = doc.data();
              return _ReportProduct(
                name: data['name'] as String? ?? 'Unknown product',
                stockQuantity: (data['stockQuantity'] as num?)?.toDouble() ?? 0,
              );
            })
            .where((product) => product.stockQuantity < 10)
            .toList()
          ..sort((a, b) => a.stockQuantity.compareTo(b.stockQuantity));

    final stockPurchased = scopedPurchases.fold<double>(
      0,
      (total, purchase) => total + purchase.quantity,
    );
    final expensesTotal = scopedExpenses.fold<double>(0, (total, doc) {
      return total + ((doc.data()['amount'] as num?)?.toDouble() ?? 0);
    });
    final grossProfit = salesTotal - expensesTotal;

    return _ReportData(
      salesCount: scopedSales.length + scopedOnlineOrders.length,
      salesTotal: salesTotal,
      posSalesTotal: posSalesTotal,
      onlineSalesTotal: onlineSalesTotal,
      itemsSold: itemsSold,
      stockPurchased: stockPurchased,
      expensesTotal: expensesTotal,
      discountsTotal: discountsTotal,
      taxTotal: taxTotal,
      grossProfit: grossProfit,
      sales: scopedSales,
      paymentTotals: paymentTotals,
      topProducts: topProducts.take(8).toList(),
      lowStockProducts: lowStockProducts.take(8).toList(),
      recentPurchases: scopedPurchases.take(8).toList(),
    );
  }
}

class _SaleRecord {
  final String businessId;
  final String title;
  final double total;
  final double discount;
  final double tax;
  final String paymentMethod;
  final DateTime date;
  final List<_SoldItem> items;

  const _SaleRecord({
    required this.businessId,
    required this.title,
    required this.total,
    required this.discount,
    required this.tax,
    required this.paymentMethod,
    required this.date,
    required this.items,
  });

  factory _SaleRecord.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final items = _decodeItems(data['itemsJson']);
    final title = items.isEmpty
        ? 'Sale ${doc.id}'
        : items
              .take(2)
              .map(
                (item) => '${item.quantity.toStringAsFixed(0)}x ${item.name}',
              )
              .join(', ');

    return _SaleRecord(
      businessId: data['businessId'] as String? ?? 'default_business',
      title: title,
      total: (data['totalAmount'] as num?)?.toDouble() ?? 0,
      discount: (data['discountAmount'] as num?)?.toDouble() ?? 0,
      tax: (data['taxAmount'] as num?)?.toDouble() ?? 0,
      paymentMethod: data['paymentMethod'] as String? ?? 'Unknown',
      date: _dateFromValue(data['timestamp']),
      items: items,
    );
  }
}

class _ProductSales {
  final String name;
  final double quantity;

  const _ProductSales(this.name, this.quantity);
}

class _ReportProduct {
  final String name;
  final double stockQuantity;

  const _ReportProduct({required this.name, required this.stockQuantity});
}

class _PurchaseSummary {
  final String businessId;
  final String productName;
  final double quantity;
  final DateTime date;

  const _PurchaseSummary({
    required this.businessId,
    required this.productName,
    required this.quantity,
    required this.date,
  });

  factory _PurchaseSummary.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return _PurchaseSummary(
      businessId: data['businessId'] as String? ?? 'default_business',
      productName: data['productName'] as String? ?? 'Unknown product',
      quantity: (data['quantity'] as num?)?.toDouble() ?? 0,
      date: _dateFromValue(data['createdAt']),
    );
  }
}

class _SoldItem {
  final String name;
  final double quantity;

  const _SoldItem({required this.name, required this.quantity});
}

List<_SoldItem> _decodeItems(dynamic value) {
  if (value is! String || value.isEmpty) return [];

  try {
    final decoded = jsonDecode(value);
    if (decoded is! List) return [];

    return decoded
        .map((item) {
          if (item is! Map) return null;
          final name = item['name'] as String?;
          if (name == null || name.isEmpty) return null;
          final quantity = (item['quantity'] as num?)?.toDouble() ?? 1;
          return _SoldItem(name: name, quantity: quantity);
        })
        .whereType<_SoldItem>()
        .toList();
  } catch (_) {
    return [];
  }
}

DateTime _dateFromValue(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

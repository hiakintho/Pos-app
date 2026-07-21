import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'app_loading_indicator.dart';
import 'package:intl/intl.dart';

import 'models.dart';
import 'notification_inbox_page.dart';
import 'ai_service.dart';

class DashboardScreen extends StatelessWidget {
  final User user;
  final VoidCallback? onOpenMenu;
  final Map<String, bool>? permissions;
  const DashboardScreen({
    super.key,
    required this.user,
    this.onOpenMenu,
    this.permissions,
  });

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
        actions: [NotificationBellButton(user: user)],
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
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('customer_orders')
                        .snapshots(),
                    builder: (context, onlineSnapshot) {
                      if (productSnapshot.hasError ||
                          salesSnapshot.hasError ||
                          purchaseSnapshot.hasError ||
                          onlineSnapshot.hasError) {
                        return const Center(
                          child: Text(
                            'Could not load dashboard data from Firebase.',
                          ),
                        );
                      }
                      if (!productSnapshot.hasData ||
                          !salesSnapshot.hasData ||
                          !purchaseSnapshot.hasData ||
                          !onlineSnapshot.hasData) {
                        return const Center(child: ModernLoadingIndicator());
                      }
                      final data = _DashboardData.fromSnapshots(
                        productSnapshot.data!.docs,
                        salesSnapshot.data!.docs,
                        purchaseSnapshot.data!.docs,
                        onlineSnapshot.data!.docs,
                        user.businessId ?? 'default_business',
                      );
                      return _DashboardContent(
                        user: user,
                        data: data,
                        aiEnabled:
                            user.role == UserRole.superAdmin ||
                            permissions == null ||
                            permissions!['ai_business_advisor'] == true,
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

class _DashboardContent extends StatelessWidget {
  final User user;
  final _DashboardData data;
  final bool aiEnabled;

  const _DashboardContent({
    required this.user,
    required this.data,
    required this.aiEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(
      locale: 'sw_TZ',
      symbol: 'Tsh ',
      decimalDigits: 0,
    );
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
                      title: 'Total Sales (All Channels)',
                      value: currencyFormat.format(data.salesTotal),
                      icon: Icons.payments,
                      color: Colors.green,
                    ),
                    _StatCard(
                      title: 'POS Sales',
                      value: currencyFormat.format(data.posSalesTotal),
                      icon: Icons.point_of_sale,
                      color: Colors.blue,
                    ),
                    _StatCard(
                      title: 'Online Sales',
                      value: currencyFormat.format(data.onlineSalesTotal),
                      icon: Icons.shopping_bag,
                      color: Colors.purple,
                    ),
                    _StatCard(
                      title: 'All Transactions',
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
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _InsightCard(
                  title: 'Most sold product',
                  value: data.mostSoldProduct,
                  detail: '${data.mostSoldUnits.toStringAsFixed(0)} units',
                  icon: Icons.emoji_events,
                  color: Colors.green,
                ),
                _InsightCard(
                  title: 'Least sold product',
                  value: data.leastSoldProduct,
                  detail: '${data.leastSoldUnits.toStringAsFixed(0)} units',
                  icon: Icons.trending_down,
                  color: Colors.orange,
                ),
                _InsightCard(
                  title: 'Average product sales',
                  value: data.averageUnitsSold.toStringAsFixed(1),
                  detail: 'units per inventory product',
                  icon: Icons.analytics,
                  color: Colors.blue,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (aiEnabled) ...[
              _AiAdviceCard(data: data),
              const SizedBox(height: 20),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 900;
                final charts = [
                  _PieChartCard(
                    title: 'Payment Mix',
                    subtitle: 'Cash, credit, and other payment totals',
                    slices: data.paymentMix,
                    emptyMessage: 'No sales payment data yet.',
                  ),
                  _BarChartCard(
                    title: 'Sales Trend',
                    subtitle: 'Daily sales value from recent transactions',
                    bars: data.dailySales,
                    valueFormat: currencyFormat,
                    emptyMessage: 'No recent sales to chart.',
                  ),
                  _PieChartCard(
                    title: 'Inventory Categories',
                    subtitle: 'Products grouped by category',
                    slices: data.categoryMix,
                    emptyMessage: 'No products to chart.',
                  ),
                  _BarChartCard(
                    title: 'Stock Purchases',
                    subtitle: 'Quantity received by day',
                    bars: data.purchaseTrend,
                    emptyMessage: 'No purchase movement yet.',
                  ),
                ];

                if (!isDesktop) {
                  return Column(
                    children: [
                      for (final chart in charts) ...[
                        chart,
                        const SizedBox(height: 12),
                      ],
                    ],
                  );
                }

                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.65,
                  children: charts,
                );
              },
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

class _PieChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<_ChartValue> slices;
  final String emptyMessage;

  const _PieChartCard({
    required this.title,
    required this.subtitle,
    required this.slices,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty) return _EmptyCard(message: emptyMessage);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ChartTitle(title: title, subtitle: subtitle),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: CustomPaint(
                      painter: _PieChartPainter(slices),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: _ChartLegend(values: slices)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<_ChartValue> bars;
  final NumberFormat? valueFormat;
  final String emptyMessage;

  const _BarChartCard({
    required this.title,
    required this.subtitle,
    required this.bars,
    this.valueFormat,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) return _EmptyCard(message: emptyMessage);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ChartTitle(title: title, subtitle: subtitle),
            const SizedBox(height: 12),
            Expanded(
              child: CustomPaint(
                painter: _BarChartPainter(bars),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _chartRangeText(bars, valueFormat),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _ChartTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ChartLegend extends StatelessWidget {
  final List<_ChartValue> values;

  const _ChartLegend({required this.values});

  @override
  Widget build(BuildContext context) {
    final total = values.fold<double>(0, (amount, item) {
      return amount + item.value;
    });
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: values.take(5).map((item) {
        final percent = total == 0 ? 0 : item.value / total * 100;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: item.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${percent.toStringAsFixed(0)}%'),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final List<_ChartValue> values;

  const _PieChartPainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (amount, item) {
      return amount + item.value;
    });
    if (total <= 0) return;

    final shortest = math.min(size.width, size.height);
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: shortest,
      height: shortest,
    ).deflate(8);
    final paint = Paint()..style = PaintingStyle.stroke;
    paint.strokeWidth = math.max(18, shortest * 0.18);
    paint.strokeCap = StrokeCap.butt;

    var start = -math.pi / 2;
    for (final value in values) {
      final sweep = value.value / total * math.pi * 2;
      paint.color = value.color;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }

    final holePaint = Paint()..color = const Color(0xFF181818);
    canvas.drawCircle(rect.center, rect.width * 0.24, holePaint);
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) {
    return oldDelegate.values != values;
  }
}

class _BarChartPainter extends CustomPainter {
  final List<_ChartValue> values;

  const _BarChartPainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = values.fold<double>(
      0,
      (current, item) => math.max(current, item.value),
    );
    if (maxValue <= 0) return;

    final axisPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    final barPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [Color(0xFF1DB954), Color(0xFF4BE477)],
      ).createShader(Offset.zero & size);

    const bottomLabelSpace = 24.0;
    final chartHeight = size.height - bottomLabelSpace;
    final step = size.width / values.length;
    final barWidth = math.min(44.0, step * 0.58);

    canvas.drawLine(
      Offset(0, chartHeight),
      Offset(size.width, chartHeight),
      axisPaint,
    );

    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      final left = i * step + (step - barWidth) / 2;
      final height = chartHeight * (value.value / maxValue);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, chartHeight - height, barWidth, height),
        const Radius.circular(5),
      );
      canvas.drawRRect(rect, barPaint);

      final labelPainter = TextPainter(
        text: TextSpan(
          text: value.label,
          style: const TextStyle(color: Color(0xFFB3B3B3), fontSize: 10),
        ),
        maxLines: 1,
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: step);
      labelPainter.paint(
        canvas,
        Offset(i * step + (step - labelPainter.width) / 2, chartHeight + 6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) {
    return oldDelegate.values != values;
  }
}

String _chartRangeText(List<_ChartValue> values, NumberFormat? format) {
  final total = values.fold<double>(0, (amount, item) {
    return amount + item.value;
  });
  final top = values.reduce((a, b) => a.value >= b.value ? a : b);
  final totalText = format == null
      ? total.toStringAsFixed(0)
      : format.format(total);
  final topText = format == null
      ? top.value.toStringAsFixed(0)
      : format.format(top.value);
  return 'Total $totalText | Highest ${top.label}: $topText';
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

class _InsightCard extends StatelessWidget {
  final String title;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;
  const _InsightCard({
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 300,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: .15),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(value, style: Theme.of(context).textTheme.titleMedium),
                  Text(detail, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AiAdviceCard extends StatefulWidget {
  final _DashboardData data;
  const _AiAdviceCard({required this.data});

  @override
  State<_AiAdviceCard> createState() => _AiAdviceCardState();
}

class _AiAdviceCardState extends State<_AiAdviceCard> {
  String? advice;
  bool loading = false;

  Future<void> analyze() async {
    setState(() => loading = true);
    try {
      final data = widget.data;
      final result = await AiService.instance.businessAdvice({
        'totalSales': data.salesTotal,
        'posSales': data.posSalesTotal,
        'onlineSales': data.onlineSalesTotal,
        'transactions': data.salesCount,
        'productCount': data.productCount,
        'lowStockCount': data.lowStockCount,
        'mostSoldProduct': data.mostSoldProduct,
        'mostSoldUnits': data.mostSoldUnits,
        'leastSoldProduct': data.leastSoldProduct,
        'leastSoldUnits': data.leastSoldUnits,
        'averageUnitsSold': data.averageUnitsSold,
        'recentPurchaseCount': data.recentPurchases.length,
      });
      if (mounted) setState(() => advice = result);
    } catch (e) {
      if (mounted) {
        setState(
          () => advice =
              'AI analysis is unavailable. Verify that the Gemini Cloud Function and secret are deployed. ($e)',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.deepPurple),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI Business Advisor',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              FilledButton.icon(
                onPressed: loading ? null : analyze,
                icon: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ModernLoadingIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.psychology),
                label: Text(
                  advice == null ? 'Analyze business' : 'Refresh advice',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            advice ??
                'Generate data-based recommendations for stock, cash flow, cost reduction, and operating best practices.',
          ),
          const SizedBox(height: 6),
          Text(
            'Advice supports decisions; review figures before changing prices, stock, payroll, or payments.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

class _DashboardData {
  final int productCount;
  final int lowStockCount;
  final int salesCount;
  final double salesTotal;
  final double posSalesTotal;
  final double onlineSalesTotal;
  final int posSalesCount;
  final int onlineSalesCount;
  final List<Product> lowStockProducts;
  final List<_SaleSummary> recentSales;
  final List<_PurchaseSummary> recentPurchases;
  final List<_ChartValue> paymentMix;
  final List<_ChartValue> categoryMix;
  final List<_ChartValue> dailySales;
  final List<_ChartValue> purchaseTrend;
  final String mostSoldProduct;
  final double mostSoldUnits;
  final String leastSoldProduct;
  final double leastSoldUnits;
  final double averageUnitsSold;

  const _DashboardData({
    required this.productCount,
    required this.lowStockCount,
    required this.salesCount,
    required this.salesTotal,
    required this.posSalesTotal,
    required this.onlineSalesTotal,
    required this.posSalesCount,
    required this.onlineSalesCount,
    required this.lowStockProducts,
    required this.recentSales,
    required this.recentPurchases,
    required this.paymentMix,
    required this.categoryMix,
    required this.dailySales,
    required this.purchaseTrend,
    required this.mostSoldProduct,
    required this.mostSoldUnits,
    required this.leastSoldProduct,
    required this.leastSoldUnits,
    required this.averageUnitsSold,
  });

  factory _DashboardData.fromSnapshots(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> productDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> saleDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> purchaseDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> onlineOrderDocs,
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
    final onlineOrders = onlineOrderDocs.where((doc) {
      final data = doc.data();
      final shopIds = (data['shopIds'] as List? ?? const []).map(
        (value) => value.toString(),
      );
      return shopIds.contains(businessId) && data['status'] != 'cancelled';
    }).toList();
    final recentPurchases = scopedPurchaseDocs
        .map(_PurchaseSummary.fromDoc)
        .toList();
    final posSalesTotal = recentSales.fold<double>(
      0,
      (total, sale) => total + sale.total,
    );
    final onlineSalesTotal = onlineOrders.fold<double>(
      0,
      (total, order) =>
          total + ((order.data()['total'] as num?)?.toDouble() ?? 0),
    );
    final categoryCounts = <String, double>{};
    for (final product in products) {
      final category = product.category.trim().isEmpty
          ? 'General'
          : product.category.trim();
      categoryCounts.update(category, (value) => value + 1, ifAbsent: () => 1);
    }

    final paymentTotals = <String, double>{};
    for (final sale in recentSales) {
      paymentTotals.update(
        sale.paymentMethod,
        (value) => value + sale.total,
        ifAbsent: () => sale.total,
      );
    }
    if (onlineSalesTotal > 0) paymentTotals['Online'] = onlineSalesTotal;

    final unitsByProduct = <String, double>{
      for (final product in products) product.name: 0,
    };
    void collectItems(Map<String, dynamic> data) {
      for (final raw in data['items'] as List? ?? const []) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final name = (item['name'] ?? item['productName'] ?? 'Unknown product')
            .toString();
        final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
        unitsByProduct.update(
          name,
          (value) => value + quantity,
          ifAbsent: () => quantity,
        );
      }
    }

    for (final sale in scopedSaleDocs) {
      collectItems(sale.data());
    }
    for (final order in onlineOrders) {
      collectItems(order.data());
    }
    final rankedProducts = unitsByProduct.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalUnits = rankedProducts.fold<double>(
      0,
      (total, item) => total + item.value,
    );

    return _DashboardData(
      productCount: products.length,
      lowStockCount: lowStockProducts.length,
      salesCount: scopedSaleDocs.length + onlineOrders.length,
      salesTotal: posSalesTotal + onlineSalesTotal,
      posSalesTotal: posSalesTotal,
      onlineSalesTotal: onlineSalesTotal,
      posSalesCount: scopedSaleDocs.length,
      onlineSalesCount: onlineOrders.length,
      lowStockProducts: lowStockProducts.take(6).toList(),
      recentSales: recentSales.take(6).toList(),
      recentPurchases: recentPurchases.take(6).toList(),
      paymentMix: _chartValuesFromMap(paymentTotals),
      categoryMix: _chartValuesFromMap(categoryCounts),
      dailySales: _dailySalesChart(recentSales),
      purchaseTrend: _dailyPurchaseChart(recentPurchases),
      mostSoldProduct: rankedProducts.isEmpty
          ? 'No sales data'
          : rankedProducts.first.key,
      mostSoldUnits: rankedProducts.isEmpty ? 0 : rankedProducts.first.value,
      leastSoldProduct: rankedProducts.isEmpty
          ? 'No sales data'
          : rankedProducts.last.key,
      leastSoldUnits: rankedProducts.isEmpty ? 0 : rankedProducts.last.value,
      averageUnitsSold: rankedProducts.isEmpty
          ? 0
          : totalUnits / rankedProducts.length,
    );
  }
}

class _ChartValue {
  final String label;
  final double value;
  final Color color;

  const _ChartValue({
    required this.label,
    required this.value,
    required this.color,
  });
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

const List<Color> _chartColors = [
  Color(0xFF1DB954),
  Color(0xFF4CB3FF),
  Color(0xFFFFC857),
  Color(0xFFFF6B6B),
  Color(0xFFB388FF),
  Color(0xFF4ECDC4),
  Color(0xFFFF8A3D),
];

List<_ChartValue> _chartValuesFromMap(Map<String, double> values) {
  final entries = values.entries.where((entry) => entry.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return [
    for (var i = 0; i < entries.length; i++)
      _ChartValue(
        label: entries[i].key,
        value: entries[i].value,
        color: _chartColors[i % _chartColors.length],
      ),
  ];
}

List<_ChartValue> _dailySalesChart(List<_SaleSummary> sales) {
  final totals = <DateTime, double>{};
  for (final sale in sales) {
    final day = DateTime(sale.date.year, sale.date.month, sale.date.day);
    totals.update(
      day,
      (value) => value + sale.total,
      ifAbsent: () => sale.total,
    );
  }
  return _dailyChartValues(totals);
}

List<_ChartValue> _dailyPurchaseChart(List<_PurchaseSummary> purchases) {
  final totals = <DateTime, double>{};
  for (final purchase in purchases) {
    final day = DateTime(
      purchase.date.year,
      purchase.date.month,
      purchase.date.day,
    );
    totals.update(
      day,
      (value) => value + purchase.quantity,
      ifAbsent: () => purchase.quantity,
    );
  }
  return _dailyChartValues(totals);
}

List<_ChartValue> _dailyChartValues(Map<DateTime, double> values) {
  final entries = values.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final latest = entries.length > 7
      ? entries.sublist(entries.length - 7)
      : entries;
  final labelFormat = DateFormat('d MMM');
  return [
    for (var i = 0; i < latest.length; i++)
      _ChartValue(
        label: labelFormat.format(latest[i].key),
        value: latest[i].value,
        color: _chartColors[i % _chartColors.length],
      ),
  ];
}

DateTime _dateFromValue(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

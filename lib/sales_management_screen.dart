import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'app_loading_indicator.dart';
import 'package:intl/intl.dart';

import 'models.dart';
import 'notification_inbox_page.dart';
import 'pricing_settings_screen.dart';

class SalesManagementScreen extends StatelessWidget {
  final User user;
  final VoidCallback? onOpenMenu;
  const SalesManagementScreen({super.key, required this.user, this.onOpenMenu});

  String get _businessId => user.businessId ?? 'default_business';
  bool get _isOwner => user.role == UserRole.superAdmin;

  Stream<Map<String, bool>> get _permissionsStream {
    final roleDocId = '${_businessId}_${user.role}';
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
              .doc(user.role)
              .snapshots();
        })
        .map((doc) => Map<String, bool>.from(doc.data()?['permissions'] ?? {}));
  }

  bool _can(Map<String, bool> permissions, String featureId) {
    if (_isOwner) return true;
    if (permissions.isEmpty) return true;
    return permissions[featureId] == true;
  }

  void _openCustomerSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CustomerSheet(user: user),
    );
  }

  void _openDocumentSheet(BuildContext context, String type) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SalesDocumentSheet(user: user, type: type),
    );
  }

  void _openDiscountSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _DiscountSheet(user: user),
    );
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'sw_TZ',
      symbol: 'Tsh ',
      decimalDigits: 0,
    );
    final date = DateFormat('MMM d, HH:mm');

    return StreamBuilder<Map<String, bool>>(
      stream: _permissionsStream,
      builder: (context, permissionSnapshot) {
        final permissions = permissionSnapshot.data ?? {};
        final canManageTransactions = _can(
          permissions,
          'manage_sales_transactions',
        );
        final canManageDiscounts = _can(permissions, 'manage_discounts');
        final canManagePriceGroups = _can(permissions, 'manage_price_groups');
        final canMonitorBranches = _can(permissions, 'branch_sales_monitoring');

        return DefaultTabController(
          length: 5,
          child: Scaffold(
            appBar: AppBar(
              leading: onOpenMenu == null
                  ? null
                  : IconButton(
                      tooltip: 'Menu',
                      onPressed: onOpenMenu,
                      icon: const Icon(Icons.menu),
                    ),
              title: const Text('Sales Management'),
              bottom: const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'Analytics'),
                  Tab(text: 'Credit'),
                  Tab(text: 'Returns'),
                  Tab(text: 'Docs'),
                  Tab(text: 'Tools'),
                ],
              ),
              actions: [NotificationBellButton(user: user)],
            ),
            body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('sales')
                  .orderBy('timestamp', descending: true)
                  .limit(500)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: ModernLoadingIndicator());
                }
                final allDocs = snapshot.data!.docs.where((doc) {
                  final data = doc.data();
                  final businessMatch =
                      (data['businessId'] as String? ?? 'default_business') ==
                      _businessId;
                  final branchMatch =
                      canMonitorBranches ||
                      user.branchId == null ||
                      (data['branchId'] as String? ?? 'main') == user.branchId;
                  return businessMatch && branchMatch;
                }).toList();

                return TabBarView(
                  children: [
                    _SalesAnalyticsTab(
                      docs: allDocs,
                      money: money,
                      businessId: _businessId,
                    ),
                    _CreditSalesTab(
                      docs: allDocs,
                      money: money,
                      date: date,
                      canManage: canManageTransactions,
                    ),
                    _ReturnsTab(
                      docs: allDocs,
                      money: money,
                      date: date,
                      canManage: canManageTransactions,
                    ),
                    _DocumentsTab(
                      user: user,
                      money: money,
                      date: date,
                      onInvoice: () => _openDocumentSheet(context, 'invoice'),
                      onQuotation: () =>
                          _openDocumentSheet(context, 'quotation'),
                    ),
                    _ToolsTab(
                      businessId: _businessId,
                      canManageDiscounts: canManageDiscounts,
                      canManagePriceGroups: canManagePriceGroups,
                      onDiscount: () => _openDiscountSheet(context),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _SalesAnalyticsTab extends StatefulWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final NumberFormat money;
  final String businessId;

  const _SalesAnalyticsTab({
    required this.docs,
    required this.money,
    required this.businessId,
  });

  @override
  State<_SalesAnalyticsTab> createState() => _SalesAnalyticsTabState();
}

class _SalesAnalyticsTabState extends State<_SalesAnalyticsTab> {
  Future<void> _setTarget(
    BuildContext context,
    String period,
    double current,
  ) async {
    final controller = TextEditingController(
      text: current > 0 ? current.toStringAsFixed(0) : '',
    );
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set $period sales target'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Target amount (Tsh)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text)),
            child: const Text('Save target'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result <= 0) return;
    await FirebaseFirestore.instance
        .collection('businesses')
        .doc(widget.businessId)
        .collection('settings')
        .doc('sales_target')
        .set({
          'period': period,
          'amount': result,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    final analytics = _SalesAnalytics.fromDocs(widget.docs);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
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
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: columns == 1 ? 4 : 2.25,
              children: [
                _MetricCard(
                  title: 'Sales Revenue',
                  value: widget.money.format(analytics.salesTotal),
                  icon: Icons.payments,
                  color: Colors.green,
                ),
                _MetricCard(
                  title: 'Credit Balance',
                  value: widget.money.format(analytics.creditBalance),
                  icon: Icons.schedule,
                  color: Colors.orange,
                ),
                _MetricCard(
                  title: 'Returns',
                  value: widget.money.format(analytics.returnTotal),
                  icon: Icons.undo,
                  color: Colors.red,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _SalesTargetChart(
          businessId: widget.businessId,
          posDocs: widget.docs,
          money: widget.money,
          onSetTarget: _setTarget,
        ),
        const SizedBox(height: 16),
        _SimpleBreakdownCard(
          title: 'Branch-wise Sales',
          rows: analytics.branchTotals.entries
              .map(
                (entry) =>
                    _BreakdownRow(entry.key, widget.money.format(entry.value)),
              )
              .toList(),
          emptyMessage: 'No branch sales yet.',
        ),
        const SizedBox(height: 12),
        _SimpleBreakdownCard(
          title: 'Payment Methods',
          rows: analytics.paymentTotals.entries
              .map(
                (entry) =>
                    _BreakdownRow(entry.key, widget.money.format(entry.value)),
              )
              .toList(),
          emptyMessage: 'No payment data yet.',
        ),
      ],
    );
  }
}

class _SalesTargetChart extends StatelessWidget {
  final String businessId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> posDocs;
  final NumberFormat money;
  final Future<void> Function(BuildContext, String, double) onSetTarget;

  const _SalesTargetChart({
    required this.businessId,
    required this.posDocs,
    required this.money,
    required this.onSetTarget,
  });

  DateTime _asDate(dynamic value) => value is Timestamp
      ? value.toDate()
      : DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('businesses')
        .doc(businessId)
        .collection('settings')
        .doc('sales_target')
        .snapshots(),
    builder: (context, targetSnapshot) =>
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('customer_orders')
              .snapshots(),
          builder: (context, orderSnapshot) {
            final targetData =
                targetSnapshot.data?.data() ?? const <String, dynamic>{};
            final period = (targetData['period'] ?? 'daily').toString();
            final amount = (targetData['amount'] as num?)?.toDouble() ?? 0;
            final dailyTarget = period == 'weekly'
                ? amount / 7
                : period == 'monthly'
                ? amount / 30
                : amount;
            final now = DateTime.now();
            final days = List.generate(
              7,
              (index) => DateTime(
                now.year,
                now.month,
                now.day,
              ).subtract(Duration(days: 6 - index)),
            );
            final pos = <DateTime, double>{};
            final online = <DateTime, double>{};
            for (final doc in posDocs) {
              final data = doc.data();
              final date = _asDate(data['timestamp']);
              final day = DateTime(date.year, date.month, date.day);
              pos.update(
                day,
                (value) =>
                    value + ((data['totalAmount'] as num?)?.toDouble() ?? 0),
                ifAbsent: () => (data['totalAmount'] as num?)?.toDouble() ?? 0,
              );
            }
            for (final doc in orderSnapshot.data?.docs ?? const []) {
              final data = doc.data();
              final shops = (data['shopIds'] as List? ?? const []).map(
                (item) => item.toString(),
              );
              if (!shops.contains(businessId) || data['status'] == 'cancelled')
                continue;
              final date = _asDate(data['createdAt']);
              final day = DateTime(date.year, date.month, date.day);
              online.update(
                day,
                (value) => value + ((data['total'] as num?)?.toDouble() ?? 0),
                ifAbsent: () => (data['total'] as num?)?.toDouble() ?? 0,
              );
            }
            final maximum = [
              dailyTarget,
              ...days.map((day) => (pos[day] ?? 0) + (online[day] ?? 0)),
            ].fold<double>(1, (a, b) => a > b ? a : b);
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'POS and Online Sales vs Target',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        DropdownButton<String>(
                          value: period,
                          items: const [
                            DropdownMenuItem(
                              value: 'daily',
                              child: Text('Daily'),
                            ),
                            DropdownMenuItem(
                              value: 'weekly',
                              child: Text('Weekly'),
                            ),
                            DropdownMenuItem(
                              value: 'monthly',
                              child: Text('Monthly'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null)
                              onSetTarget(
                                context,
                                value,
                                value == period ? amount : 0,
                              );
                          },
                        ),
                        OutlinedButton.icon(
                          onPressed: () => onSetTarget(context, period, amount),
                          icon: const Icon(Icons.flag_outlined),
                          label: const Text('Set target'),
                        ),
                      ],
                    ),
                    Text(
                      amount > 0
                          ? '${period[0].toUpperCase()}${period.substring(1)} target: ${money.format(amount)}'
                          : 'No sales target set',
                    ),
                    const SizedBox(height: 12),
                    ...days.map((day) {
                      final posValue = pos[day] ?? 0;
                      final onlineValue = online[day] ?? 0;
                      final posFlex = ((posValue / maximum) * 1000)
                          .round()
                          .clamp(1, 1000)
                          .toInt();
                      final onlineFlex = ((onlineValue / maximum) * 1000)
                          .round()
                          .clamp(1, 1000)
                          .toInt();
                      final emptyFlex = (1000 - posFlex - onlineFlex)
                          .clamp(1, 1000)
                          .toInt();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${DateFormat('EEE, d MMM').format(day)}  •  POS ${money.format(posValue)}  •  Online ${money.format(onlineValue)}',
                            ),
                            const SizedBox(height: 5),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: posFlex,
                                    child: Container(
                                      height: 12,
                                      color: Colors.blue,
                                    ),
                                  ),
                                  Expanded(
                                    flex: onlineFlex,
                                    child: Container(
                                      height: 12,
                                      color: Colors.purple,
                                    ),
                                  ),
                                  Expanded(
                                    flex: emptyFlex,
                                    child: Container(
                                      height: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (dailyTarget > 0)
                              Text(
                                '${money.format(posValue + onlineValue)} of ${money.format(dailyTarget)} daily equivalent',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    const Wrap(
                      spacing: 16,
                      children: [
                        Text('■ POS', style: TextStyle(color: Colors.blue)),
                        Text(
                          '■ Online',
                          style: TextStyle(color: Colors.purple),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
  );
}

class _SalesList extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final NumberFormat money;
  final DateFormat date;
  final bool canManage;

  const _SalesList({
    required this.docs,
    required this.money,
    required this.date,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context) {
    final visible = docs.where((doc) {
      final data = doc.data();
      return (data['status'] as String? ?? 'completed') != 'returned';
    }).toList();
    if (visible.isEmpty) return const Center(child: Text('No sales yet.'));
    return ListView.separated(
      itemCount: visible.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _SaleTile(
        doc: visible[index],
        money: money,
        date: date,
        canManage: canManage,
      ),
    );
  }
}

class _CreditSalesTab extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final NumberFormat money;
  final DateFormat date;
  final bool canManage;

  const _CreditSalesTab({
    required this.docs,
    required this.money,
    required this.date,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context) {
    final creditDocs = docs.where((doc) => _isCreditSale(doc.data())).toList();
    if (creditDocs.isEmpty) {
      return const Center(child: Text('No credit sales yet.'));
    }
    return ListView.separated(
      itemCount: creditDocs.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _SaleTile(
        doc: creditDocs[index],
        money: money,
        date: date,
        canManage: canManage,
        forceCreditActions: true,
      ),
    );
  }
}

class _ReturnsTab extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final NumberFormat money;
  final DateFormat date;
  final bool canManage;

  const _ReturnsTab({
    required this.docs,
    required this.money,
    required this.date,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context) {
    final returns = docs.where((doc) {
      final data = doc.data();
      return (data['status'] as String? ?? '') == 'returned';
    }).toList();
    if (returns.isEmpty) return const Center(child: Text('No returns yet.'));
    return ListView.separated(
      itemCount: returns.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _SaleTile(
        doc: returns[index],
        money: money,
        date: date,
        canManage: canManage,
      ),
    );
  }
}

class _DeliveryTab extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final DateFormat date;
  final bool canManage;

  const _DeliveryTab({
    required this.docs,
    required this.date,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) return const Center(child: Text('No deliveries yet.'));
    return ListView.separated(
      itemCount: docs.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final doc = docs[index];
        final data = doc.data();
        final deliveryStatus = data['deliveryStatus'] as String? ?? 'not_set';
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.local_shipping)),
          title: Text(_saleTitle(data['itemsJson'])),
          subtitle: Text(
            '${date.format(_date(data['timestamp']))} | ${deliveryStatus.replaceAll('_', ' ')}',
          ),
          trailing: canManage
              ? DropdownButton<String>(
                  value: deliveryStatus,
                  items: const [
                    DropdownMenuItem(value: 'not_set', child: Text('Not set')),
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(
                      value: 'dispatched',
                      child: Text('Dispatched'),
                    ),
                    DropdownMenuItem(
                      value: 'delivered',
                      child: Text('Delivered'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    doc.reference.update({
                      'deliveryStatus': value,
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
                  },
                )
              : Text(deliveryStatus),
        );
      },
    );
  }
}

class _SaleTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final NumberFormat money;
  final DateFormat date;
  final bool canManage;
  final bool forceCreditActions;

  const _SaleTile({
    required this.doc,
    required this.money,
    required this.date,
    required this.canManage,
    this.forceCreditActions = false,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final total = (data['totalAmount'] as num?)?.toDouble() ?? 0;
    final paid = (data['paidAmount'] as num?)?.toDouble() ?? 0;
    final creditPaid = (data['creditPaidAmount'] as num?)?.toDouble() ?? 0;
    final isCredit = _isCreditSale(data);
    final status = data['status'] as String? ?? 'completed';
    final balance = (total - paid - creditPaid).clamp(0, double.infinity);
    final paymentStatus =
        data['paymentStatus'] as String? ??
        (isCredit ? (balance <= 0 ? 'paid' : 'unpaid') : 'paid');

    return ListTile(
      leading: CircleAvatar(
        child: Icon(isCredit ? Icons.schedule : Icons.receipt_long),
      ),
      title: Text(_saleTitle(data['itemsJson'])),
      subtitle: Text(
        '${data['paymentMethod'] ?? 'Unknown'} | ${date.format(_date(data['timestamp']))} | $paymentStatus | Branch ${data['branchId'] ?? 'main'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: SizedBox(
        width: canManage ? 250 : 116,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money.format(total),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (isCredit)
                    Text(
                      'Bal ${money.format(balance)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                ],
              ),
            ),
            if (canManage && status != 'returned')
              IconButton(
                tooltip: 'Return sale',
                visualDensity: VisualDensity.compact,
                onPressed: () => _markReturned(context, doc),
                icon: const Icon(Icons.undo),
              ),
            if (canManage && (isCredit || forceCreditActions))
              IconButton(
                tooltip: 'Record credit payment',
                visualDensity: VisualDensity.compact,
                onPressed: () => _recordCreditPayment(context, doc, money),
                icon: const Icon(Icons.payments),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _recordCreditPayment(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    NumberFormat money,
  ) async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record Payment'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Amount received',
            border: OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (amount == null || amount <= 0) return;

    final data = doc.data();
    final total = (data['totalAmount'] as num?)?.toDouble() ?? 0;
    final paid = (data['paidAmount'] as num?)?.toDouble() ?? 0;
    final creditPaid = (data['creditPaidAmount'] as num?)?.toDouble() ?? 0;
    final newCreditPaid = creditPaid + amount;
    final balance = (total - paid - newCreditPaid).clamp(0, double.infinity);
    await doc.reference.update({
      'creditPaidAmount': newCreditPaid,
      'paymentStatus': balance <= 0 ? 'paid' : 'partial',
      'lastCreditPaymentAmount': amount,
      'lastCreditPaymentAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Recorded ${money.format(amount)} payment.')),
    );
  }

  Future<void> _markReturned(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Return Sale'),
        content: const Text('Mark this sale as returned?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Return'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await doc.reference.update({
      'status': 'returned',
      'returnedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

class _CustomersTab extends StatelessWidget {
  final String businessId;
  const _CustomersTab({required this.businessId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('customers')
          .orderBy('name')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: ModernLoadingIndicator());
        }
        final docs = snapshot.data!.docs.where((doc) {
          return (doc.data()['businessId'] as String? ?? 'default_business') ==
              businessId;
        }).toList();
        if (docs.isEmpty) return const Center(child: Text('No customers yet.'));
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final data = docs[index].data();
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(data['name'] as String? ?? 'Customer'),
              subtitle: Text(
                '${data['phone'] ?? 'No phone'} | ${data['address'] ?? 'No address'}',
              ),
            );
          },
        );
      },
    );
  }
}

class _DocumentsTab extends StatelessWidget {
  final User user;
  final NumberFormat money;
  final DateFormat date;
  final VoidCallback onInvoice;
  final VoidCallback onQuotation;

  const _DocumentsTab({
    required this.user,
    required this.money,
    required this.date,
    required this.onInvoice,
    required this.onQuotation,
  });

  @override
  Widget build(BuildContext context) {
    final businessId = user.businessId ?? 'default_business';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onInvoice,
                  icon: const Icon(Icons.description),
                  label: const Text('New Invoice'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onQuotation,
                  icon: const Icon(Icons.request_quote),
                  label: const Text('New Quotation'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('sales_documents')
                .orderBy('createdAt', descending: true)
                .limit(200)
                .snapshots(),
            builder: (context, snapshot) {
              final docs =
                  snapshot.data?.docs.where((doc) {
                    return (doc.data()['businessId'] as String? ??
                            'default_business') ==
                        businessId;
                  }).toList() ??
                  const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              if (docs.isEmpty) {
                return const Center(
                  child: Text('No invoices or quotations yet.'),
                );
              }
              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final data = docs[index].data();
                  final total = (data['totalAmount'] as num?)?.toDouble() ?? 0;
                  return ListTile(
                    leading: CircleAvatar(
                      child: Icon(
                        data['type'] == 'quotation'
                            ? Icons.request_quote
                            : Icons.description,
                      ),
                    ),
                    title: Text(data['customerName'] as String? ?? 'Customer'),
                    subtitle: Text(
                      '${data['type'] ?? 'invoice'} | ${data['status'] ?? 'draft'} | ${date.format(_date(data['createdAt']))}',
                    ),
                    trailing: Text(money.format(total)),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ToolsTab extends StatelessWidget {
  final String businessId;
  final bool canManageDiscounts;
  final bool canManagePriceGroups;
  final VoidCallback onDiscount;

  const _ToolsTab({
    required this.businessId,
    required this.canManageDiscounts,
    required this.canManagePriceGroups,
    required this.onDiscount,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.discount)),
          title: const Text('Discount Management'),
          subtitle: const Text('Create manual sales discounts and offers'),
          enabled: canManageDiscounts,
          onTap: canManageDiscounts ? onDiscount : null,
        ),
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.local_offer)),
          title: const Text('Price Group Management'),
          subtitle: const Text('Manage discounts, offers, and price increases'),
          enabled: canManagePriceGroups,
          onTap: canManagePriceGroups
              ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        PriceGroupManagementPage(businessId: businessId),
                  ),
                )
              : null,
        ),
      ],
    );
  }
}

class _CustomerSheet extends StatefulWidget {
  final User user;
  const _CustomerSheet({required this.user});

  @override
  State<_CustomerSheet> createState() => _CustomerSheetState();
}

class _CustomerSheetState extends State<_CustomerSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _aliases = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _aliases.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    await FirebaseFirestore.instance.collection('customers').add({
      'businessId': widget.user.businessId ?? 'default_business',
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'address': _address.text.trim(),
      'aliases': _aliases.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': widget.user.id,
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      title: 'Add Customer',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(_name, 'Customer name'),
          const SizedBox(height: 12),
          _field(_phone, 'Phone', required: false),
          const SizedBox(height: 12),
          _field(_address, 'Address', required: false),
          const SizedBox(height: 12),
          _field(_aliases, 'Search aliases (comma separated)', required: false),
          const SizedBox(height: 16),
          _saveButton(_isSaving, _save, 'Save Customer'),
        ],
      ),
    );
  }
}

class _SalesDocumentSheet extends StatefulWidget {
  final User user;
  final String type;

  const _SalesDocumentSheet({required this.user, required this.type});

  @override
  State<_SalesDocumentSheet> createState() => _SalesDocumentSheetState();
}

class _SalesDocumentSheetState extends State<_SalesDocumentSheet> {
  final _customer = TextEditingController();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _customer.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (_customer.text.trim().isEmpty || amount == null) return;
    setState(() => _isSaving = true);
    await FirebaseFirestore.instance.collection('sales_documents').add({
      'businessId': widget.user.businessId ?? 'default_business',
      'branchId': widget.user.branchId ?? 'main',
      'type': widget.type,
      'customerName': _customer.text.trim(),
      'totalAmount': amount,
      'status': 'draft',
      'notes': _notes.text.trim(),
      'createdBy': widget.user.id,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      title: widget.type == 'quotation' ? 'New Quotation' : 'New Invoice',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(_customer, 'Customer name'),
          const SizedBox(height: 12),
          _field(
            _amount,
            'Total amount',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          _field(_notes, 'Notes', required: false),
          const SizedBox(height: 16),
          _saveButton(_isSaving, _save, 'Save'),
        ],
      ),
    );
  }
}

class _DiscountSheet extends StatefulWidget {
  final User user;
  const _DiscountSheet({required this.user});

  @override
  State<_DiscountSheet> createState() => _DiscountSheetState();
}

class _DiscountSheetState extends State<_DiscountSheet> {
  final _name = TextEditingController();
  final _value = TextEditingController();
  String _type = 'discount_percent';
  bool _isSaving = false;

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = double.tryParse(_value.text.trim());
    if (_name.text.trim().isEmpty || value == null) return;
    setState(() => _isSaving = true);
    await FirebaseFirestore.instance.collection('price_groups').add({
      'businessId': widget.user.businessId ?? 'default_business',
      'name': _name.text.trim(),
      'type': _type,
      'value': value,
      'productIds': <String>[],
      'categories': <String>[],
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      title: 'Discount Management',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(_name, 'Discount name'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(
              labelText: 'Discount type',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'discount_percent',
                child: Text('Discount %'),
              ),
              DropdownMenuItem(
                value: 'discount_amount',
                child: Text('Discount amount'),
              ),
            ],
            onChanged: (value) => setState(() => _type = value!),
          ),
          const SizedBox(height: 12),
          _field(
            _value,
            'Value',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 16),
          _saveButton(_isSaving, _save, 'Save Discount'),
        ],
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  final String title;
  final Widget child;

  const _Sheet({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

Widget _field(
  TextEditingController controller,
  String label, {
  bool required = true,
  TextInputType? keyboardType,
}) {
  return TextFormField(
    controller: controller,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    validator: required
        ? (value) => value == null || value.trim().isEmpty ? 'Required' : null
        : null,
  );
}

Widget _saveButton(bool isSaving, VoidCallback onPressed, String label) {
  return SizedBox(
    width: double.infinity,
    height: 48,
    child: FilledButton.icon(
      onPressed: isSaving ? null : onPressed,
      icon: const Icon(Icons.save),
      label: Text(isSaving ? 'Saving...' : label),
    ),
  );
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.14),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
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

class _SimpleBreakdownCard extends StatelessWidget {
  final String title;
  final List<_BreakdownRow> rows;
  final String emptyMessage;

  const _SimpleBreakdownCard({
    required this.title,
    required this.rows,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const Divider(height: 20),
            if (rows.isEmpty)
              Text(emptyMessage)
            else
              ...rows.map(
                (row) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(child: Text(row.label)),
                      Text(
                        row.value,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownRow {
  final String label;
  final String value;

  const _BreakdownRow(this.label, this.value);
}

class _SalesAnalytics {
  final int salesCount;
  final double salesTotal;
  final double creditBalance;
  final double returnTotal;
  final Map<String, double> branchTotals;
  final Map<String, double> paymentTotals;

  const _SalesAnalytics({
    required this.salesCount,
    required this.salesTotal,
    required this.creditBalance,
    required this.returnTotal,
    required this.branchTotals,
    required this.paymentTotals,
  });

  factory _SalesAnalytics.fromDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var count = 0;
    var total = 0.0;
    var creditBalance = 0.0;
    var returns = 0.0;
    final branchTotals = <String, double>{};
    final paymentTotals = <String, double>{};

    for (final doc in docs) {
      final data = doc.data();
      final amount = (data['totalAmount'] as num?)?.toDouble() ?? 0;
      final status = data['status'] as String? ?? 'completed';
      if (status == 'returned') {
        returns += amount;
        continue;
      }
      count++;
      total += amount;
      final branch = data['branchId'] as String? ?? 'main';
      final payment = data['paymentMethod'] as String? ?? 'Unknown';
      branchTotals.update(
        branch,
        (value) => value + amount,
        ifAbsent: () => amount,
      );
      paymentTotals.update(
        payment,
        (value) => value + amount,
        ifAbsent: () => amount,
      );
      if (_isCreditSale(data)) {
        final paid = (data['paidAmount'] as num?)?.toDouble() ?? 0;
        final creditPaid = (data['creditPaidAmount'] as num?)?.toDouble() ?? 0;
        creditBalance += (amount - paid - creditPaid).clamp(0, double.infinity);
      }
    }

    return _SalesAnalytics(
      salesCount: count,
      salesTotal: total,
      creditBalance: creditBalance,
      returnTotal: returns,
      branchTotals: branchTotals,
      paymentTotals: paymentTotals,
    );
  }
}

bool _isCreditSale(Map<String, dynamic> data) {
  return data['isCredit'] == true ||
      data['isCredit'] == 1 ||
      data['paymentMethod'] == 'Credit';
}

String _saleTitle(dynamic itemsJson) {
  if (itemsJson is! String) return 'Sale';
  try {
    final decoded = jsonDecode(itemsJson);
    if (decoded is! List) return 'Sale';
    final title = decoded
        .take(2)
        .map((item) {
          if (item is! Map) return null;
          return '${item['quantity'] ?? 1}x ${item['name'] ?? 'Item'}';
        })
        .whereType<String>()
        .join(', ');
    return title.isEmpty ? 'Sale' : title;
  } catch (_) {
    return 'Sale';
  }
}

DateTime _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

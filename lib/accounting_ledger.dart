import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'app_loading_indicator.dart';
import 'package:intl/intl.dart';

import 'models.dart';

class AccountingLedger extends StatefulWidget {
  final User user;

  const AccountingLedger({super.key, required this.user});

  @override
  State<AccountingLedger> createState() => _AccountingLedgerState();
}

class _AccountingLedgerState extends State<AccountingLedger> {
  final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> _docs =
      {};
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _subscriptions = [];
  String _filter = 'all';
  bool _loading = true;

  String get _businessId => widget.user.businessId ?? 'default_business';

  @override
  void initState() {
    super.initState();
    for (final collection in const [
      'sales',
      'customer_orders',
      'expenses',
      'purchase_orders',
      'payroll_payments',
    ]) {
      _subscriptions.add(
        FirebaseFirestore.instance
            .collection(collection)
            .snapshots()
            .listen(
              (snapshot) {
                if (!mounted) return;
                setState(() {
                  _docs[collection] = snapshot.docs;
                  _loading = false;
                });
              },
              onError: (Object error) {
                debugPrint('Could not load $collection for accounting: $error');
                if (mounted) setState(() => _loading = false);
              },
            ),
      );
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  List<_LedgerTransaction> get _transactions {
    final transactions = <_LedgerTransaction>[];
    for (final doc in _docs['sales'] ?? const []) {
      final data = doc.data();
      if (_text(data['businessId']) != _businessId) continue;
      transactions.add(
        _LedgerTransaction(
          id: doc.id,
          source: 'POS sale',
          description:
              'POS sale${_text(data['customerName']).isEmpty ? '' : ' - ${_text(data['customerName'])}'}',
          amount: _amount(data['totalAmount']),
          income: true,
          date: _date(data['timestamp'] ?? data['createdAt']),
        ),
      );
    }
    for (final doc in _docs['customer_orders'] ?? const []) {
      final data = doc.data();
      final shopIds = (data['shopIds'] as List? ?? const []).map(
        (e) => e.toString(),
      );
      if (!shopIds.contains(_businessId)) continue;
      transactions.add(
        _LedgerTransaction(
          id: doc.id,
          source: 'Online sale',
          description:
              'Online order - ${_text(data['customerName'], 'Customer')}',
          amount: _amount(data['total']),
          income: true,
          date: _date(data['createdAt']),
        ),
      );
    }
    for (final doc in _docs['expenses'] ?? const []) {
      final data = doc.data();
      if (_text(data['businessId']) != _businessId) continue;
      transactions.add(
        _LedgerTransaction(
          id: doc.id,
          source: 'Expense',
          description: _text(data['title'], _text(data['category'], 'Expense')),
          amount: _amount(data['amount']) + _amount(data['transactionFee']),
          income: false,
          date: _date(data['createdAt']),
        ),
      );
    }
    for (final doc in _docs['purchase_orders'] ?? const []) {
      final data = doc.data();
      if (_text(data['businessId']) != _businessId) continue;
      if (_text(data['approvalStatus'], 'pending') == 'rejected') continue;
      transactions.add(
        _LedgerTransaction(
          id: doc.id,
          source: 'Purchase',
          description:
              '${_text(data['supplierName'], 'Supplier')} - ${_text(data['productName'], 'Goods')}',
          amount:
              _amount(data['totalAmount']) + _amount(data['transactionFee']),
          income: false,
          date: _date(data['createdAt']),
        ),
      );
    }
    for (final doc in _docs['payroll_payments'] ?? const []) {
      final data = doc.data();
      if (_text(data['businessId']) != _businessId) continue;
      transactions.add(
        _LedgerTransaction(
          id: doc.id,
          source: 'Payroll',
          description:
              '${_text(data['employeeName'], 'Employee')} salary - ${_text(data['payrollMonth'])}',
          amount: _amount(data['amount']) + _amount(data['transactionFee']),
          income: false,
          date: _date(data['paidAt']),
        ),
      );
    }
    transactions.sort((a, b) => b.date.compareTo(a.date));
    return transactions;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _docs.isEmpty) {
      return const Center(child: ModernLoadingIndicator());
    }
    final all = _transactions;
    final visible = _filter == 'all'
        ? all
        : all.where((entry) => entry.source == _filter).toList();
    final income = all
        .where((e) => e.income)
        .fold<double>(0, (total, entry) => total + entry.amount);
    final outflow = all
        .where((e) => !e.income)
        .fold<double>(0, (total, entry) => total + entry.amount);
    final money = NumberFormat.currency(
      locale: 'sw_TZ',
      symbol: 'Tsh ',
      decimalDigits: 0,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Summary('Sales income', money.format(income), Colors.green),
            _Summary('Expenses & costs', money.format(outflow), Colors.red),
            _Summary(
              'Net',
              money.format(income - outflow),
              income >= outflow ? Colors.teal : Colors.orange,
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Automatically generated from operational transactions. No manual journal entry is required.',
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _filter,
          decoration: const InputDecoration(
            labelText: 'Transaction source',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('All transactions')),
            DropdownMenuItem(value: 'POS sale', child: Text('POS sales')),
            DropdownMenuItem(value: 'Online sale', child: Text('Online sales')),
            DropdownMenuItem(value: 'Expense', child: Text('Expenses')),
            DropdownMenuItem(value: 'Purchase', child: Text('Purchases')),
            DropdownMenuItem(value: 'Payroll', child: Text('Payroll')),
          ],
          onChanged: (value) => setState(() => _filter = value ?? 'all'),
        ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('No transactions found.')),
          )
        else
          ...visible.map(
            (entry) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    entry.income ? Icons.south_west : Icons.north_east,
                  ),
                ),
                title: Text(entry.description),
                subtitle: Text(
                  '${entry.source} • ${DateFormat.yMMMd().add_Hm().format(entry.date)}',
                ),
                trailing: Text(
                  '${entry.income ? '+' : '-'}${money.format(entry.amount)}',
                  style: TextStyle(
                    color: entry.income ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Summary(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 240,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: color),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LedgerTransaction {
  final String id;
  final String source;
  final String description;
  final double amount;
  final bool income;
  final DateTime date;
  const _LedgerTransaction({
    required this.id,
    required this.source,
    required this.description,
    required this.amount,
    required this.income,
    required this.date,
  });
}

String _text(dynamic value, [String fallback = '']) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

double _amount(dynamic value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;

DateTime _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  return DateTime.tryParse(value?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

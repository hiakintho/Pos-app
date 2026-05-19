import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models.dart';

class SalesManagementScreen extends StatelessWidget {
  final User user;
  final VoidCallback? onOpenMenu;
  const SalesManagementScreen({super.key, required this.user, this.onOpenMenu});

  String get _businessId => user.businessId ?? 'default_business';

  void _openCustomerSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CustomerSheet(user: user),
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

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: onOpenMenu == null
              ? null
              : IconButton(
                  tooltip: 'Menu',
                  onPressed: onOpenMenu,
                  icon: const Icon(Icons.menu),
                ),
          title: const Text('Sales'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'All Sales'),
              Tab(text: 'Credit'),
              Tab(text: 'Customers'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Add customer',
              onPressed: () => _openCustomerSheet(context),
              icon: const Icon(Icons.person_add),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _salesList(money, date, onlyCredit: false),
            _salesList(money, date, onlyCredit: true),
            _customersList(),
          ],
        ),
      ),
    );
  }

  Widget _salesList(
    NumberFormat money,
    DateFormat date, {
    required bool onlyCredit,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('sales')
          .orderBy('timestamp', descending: true)
          .limit(300)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.where((doc) {
          final data = doc.data();
          final businessMatch =
              (data['businessId'] as String? ?? 'default_business') ==
              _businessId;
          final creditMatch =
              !onlyCredit || data['isCredit'] == true || data['isCredit'] == 1;
          return businessMatch && creditMatch;
        }).toList();
        if (docs.isEmpty) {
          return Center(
            child: Text(onlyCredit ? 'No credit sales yet.' : 'No sales yet.'),
          );
        }
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final total = (data['totalAmount'] as num?)?.toDouble() ?? 0;
            final isCredit = data['isCredit'] == true || data['isCredit'] == 1;
            return ListTile(
              leading: CircleAvatar(
                child: Icon(isCredit ? Icons.schedule : Icons.receipt_long),
              ),
              title: Text(_saleTitle(data['itemsJson'])),
              subtitle: Text(
                '${data['paymentMethod'] ?? 'Unknown'} | ${date.format(_date(data['timestamp']))}',
              ),
              trailing: Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (isCredit) const Chip(label: Text('Credit')),
                  Text(
                    money.format(total),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _customersList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('customers')
          .orderBy('name')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.where((doc) {
          return (doc.data()['businessId'] as String? ?? 'default_business') ==
              _businessId;
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
              subtitle: Text(data['phone'] as String? ?? 'No phone'),
            );
          },
        );
      },
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
  bool _isSaving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
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
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': widget.user.id,
    });
    if (mounted) Navigator.pop(context);
  }

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
                      'Add Customer',
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
              _field(_name, 'Customer name'),
              const SizedBox(height: 12),
              _field(_phone, 'Phone', required: false),
              const SizedBox(height: 12),
              _field(_address, 'Address', required: false),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: const Icon(Icons.save),
                  label: Text(_isSaving ? 'Saving...' : 'Save Customer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _saleTitle(dynamic itemsJson) {
  if (itemsJson is! String) return 'Sale';
  try {
    final decoded = jsonDecode(itemsJson);
    if (decoded is! List) return 'Sale';
    return decoded
        .take(2)
        .map((item) {
          if (item is! Map) return null;
          return '${item['quantity'] ?? 1}x ${item['name'] ?? 'Item'}';
        })
        .whereType<String>()
        .join(', ');
  } catch (_) {
    return 'Sale';
  }
}

Widget _field(
  TextEditingController controller,
  String label, {
  bool required = true,
}) {
  return TextFormField(
    controller: controller,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    validator: required
        ? (value) => value == null || value.trim().isEmpty ? 'Required' : null
        : null,
  );
}

DateTime _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

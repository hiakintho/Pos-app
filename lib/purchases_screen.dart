import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models.dart';

class PurchasesScreen extends StatefulWidget {
  final User user;
  final VoidCallback? onOpenMenu;
  const PurchasesScreen({super.key, required this.user, this.onOpenMenu});

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  String get _businessId => widget.user.businessId ?? 'default_business';

  void _openSupplierSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SupplierSheet(user: widget.user),
    );
  }

  void _openPurchaseSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PurchaseRecordSheet(user: widget.user),
    );
  }

  Future<void> _recordStockAdjustment() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _StockAdjustmentSheet(user: widget.user),
    );
  }

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('MMM d, yyyy');
    final money = NumberFormat.currency(
      locale: 'sw_TZ',
      symbol: 'Tsh ',
      decimalDigits: 0,
    );

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: widget.onOpenMenu == null
              ? null
              : IconButton(
                  tooltip: 'Menu',
                  onPressed: widget.onOpenMenu,
                  icon: const Icon(Icons.menu),
                ),
          title: const Text('Purchases'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Purchases'),
              Tab(text: 'Suppliers'),
              Tab(text: 'Adjustments'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Stock adjustment',
              onPressed: _recordStockAdjustment,
              icon: const Icon(Icons.tune),
            ),
            IconButton(
              tooltip: 'Add supplier',
              onPressed: _openSupplierSheet,
              icon: const Icon(Icons.person_add),
            ),
            IconButton(
              tooltip: 'Add purchase',
              onPressed: _openPurchaseSheet,
              icon: const Icon(Icons.add_shopping_cart),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _collectionList(
              collection: 'purchase_orders',
              empty: 'No purchase records yet.',
              itemBuilder: (data) {
                final total = (data['totalAmount'] as num?)?.toDouble() ?? 0;
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.shopping_bag)),
                  title: Text(data['supplierName'] as String? ?? 'Supplier'),
                  subtitle: Text(
                    '${data['status'] ?? 'paid'} | ${date.format(_date(data['createdAt']))}',
                  ),
                  trailing: Text(
                    money.format(total),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                );
              },
            ),
            _collectionList(
              collection: 'suppliers',
              empty: 'No suppliers yet.',
              itemBuilder: (data) => ListTile(
                leading: const CircleAvatar(child: Icon(Icons.local_shipping)),
                title: Text(data['name'] as String? ?? 'Supplier'),
                subtitle: Text(data['phone'] as String? ?? 'No phone'),
              ),
            ),
            _collectionList(
              collection: 'stock_adjustments',
              empty: 'No stock adjustments yet.',
              itemBuilder: (data) => ListTile(
                leading: const CircleAvatar(child: Icon(Icons.tune)),
                title: Text(data['productName'] as String? ?? 'Product'),
                subtitle: Text(
                  '${data['reason'] ?? 'Adjustment'} | ${date.format(_date(data['createdAt']))}',
                ),
                trailing: Text(
                  (data['quantity'] as num?)?.toDouble().toStringAsFixed(0) ??
                      '0',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _collectionList({
    required String collection,
    required String empty,
    required Widget Function(Map<String, dynamic> data) itemBuilder,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(collection)
          .orderBy('createdAt', descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.where((doc) {
          return (doc.data()['businessId'] as String? ?? 'default_business') ==
              _businessId;
        }).toList();
        if (docs.isEmpty) return Center(child: Text(empty));
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) => itemBuilder(docs[index].data()),
        );
      },
    );
  }
}

class _SupplierSheet extends StatefulWidget {
  final User user;
  const _SupplierSheet({required this.user});

  @override
  State<_SupplierSheet> createState() => _SupplierSheetState();
}

class _SupplierSheetState extends State<_SupplierSheet> {
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
    await FirebaseFirestore.instance.collection('suppliers').add({
      'businessId': widget.user.businessId ?? 'default_business',
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'address': _address.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      title: 'Add Supplier',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(_name, 'Supplier name'),
          const SizedBox(height: 12),
          _field(_phone, 'Phone', required: false),
          const SizedBox(height: 12),
          _field(_address, 'Address', required: false),
          const SizedBox(height: 16),
          _saveButton(_isSaving, _save, 'Save Supplier'),
        ],
      ),
    );
  }
}

class _PurchaseRecordSheet extends StatefulWidget {
  final User user;
  const _PurchaseRecordSheet({required this.user});

  @override
  State<_PurchaseRecordSheet> createState() => _PurchaseRecordSheetState();
}

class _PurchaseRecordSheetState extends State<_PurchaseRecordSheet> {
  final _supplier = TextEditingController();
  final _total = TextEditingController();
  final _notes = TextEditingController();
  bool _isCredit = false;
  bool _isReturn = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _supplier.dispose();
    _total.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final total = double.tryParse(_total.text.trim());
    if (_supplier.text.trim().isEmpty || total == null) return;
    setState(() => _isSaving = true);
    await FirebaseFirestore.instance.collection('purchase_orders').add({
      'businessId': widget.user.businessId ?? 'default_business',
      'branchId': widget.user.branchId ?? 'main',
      'supplierName': _supplier.text.trim(),
      'totalAmount': total,
      'status': _isReturn ? 'return' : (_isCredit ? 'credit' : 'paid'),
      'isCredit': _isCredit,
      'isReturn': _isReturn,
      'notes': _notes.text.trim(),
      'createdBy': widget.user.id,
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      title: 'Purchase Record',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(_supplier, 'Supplier name'),
          const SizedBox(height: 12),
          _field(
            _total,
            'Total amount',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Purchase on credit'),
            value: _isCredit,
            onChanged: (value) => setState(() => _isCredit = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Purchase return'),
            value: _isReturn,
            onChanged: (value) => setState(() => _isReturn = value),
          ),
          _field(_notes, 'Notes', required: false),
          const SizedBox(height: 16),
          _saveButton(_isSaving, _save, 'Save Purchase'),
        ],
      ),
    );
  }
}

class _StockAdjustmentSheet extends StatefulWidget {
  final User user;
  const _StockAdjustmentSheet({required this.user});

  @override
  State<_StockAdjustmentSheet> createState() => _StockAdjustmentSheetState();
}

class _StockAdjustmentSheetState extends State<_StockAdjustmentSheet> {
  final _product = TextEditingController();
  final _quantity = TextEditingController();
  final _reason = TextEditingController(text: 'Manual adjustment');
  bool _isSaving = false;

  @override
  void dispose() {
    _product.dispose();
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final quantity = double.tryParse(_quantity.text.trim());
    if (_product.text.trim().isEmpty || quantity == null) return;
    setState(() => _isSaving = true);
    await FirebaseFirestore.instance.collection('stock_adjustments').add({
      'businessId': widget.user.businessId ?? 'default_business',
      'branchId': widget.user.branchId ?? 'main',
      'productName': _product.text.trim(),
      'quantity': quantity,
      'reason': _reason.text.trim(),
      'createdBy': widget.user.id,
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      title: 'Stock Adjustment',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(_product, 'Product name'),
          const SizedBox(height: 12),
          _field(
            _quantity,
            'Quantity change',
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
          ),
          const SizedBox(height: 12),
          _field(_reason, 'Reason'),
          const SizedBox(height: 16),
          _saveButton(_isSaving, _save, 'Save Adjustment'),
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

DateTime _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

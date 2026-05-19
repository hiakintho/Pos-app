import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models.dart';

class ExpensesScreen extends StatelessWidget {
  final User user;
  final VoidCallback? onOpenMenu;
  const ExpensesScreen({super.key, required this.user, this.onOpenMenu});

  String get _businessId => user.businessId ?? 'default_business';

  void _openExpenseSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ExpenseSheet(user: user),
    );
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'sw_TZ',
      symbol: 'Tsh ',
      decimalDigits: 0,
    );
    final date = DateFormat('MMM d, yyyy');

    return Scaffold(
      appBar: AppBar(
        leading: onOpenMenu == null
            ? null
            : IconButton(
                tooltip: 'Menu',
                onPressed: onOpenMenu,
                icon: const Icon(Icons.menu),
              ),
        title: const Text('Expenses'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('expenses')
            .orderBy('createdAt', descending: true)
            .limit(200)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs.where((doc) {
            return (doc.data()['businessId'] as String? ??
                    'default_business') ==
                _businessId;
          }).toList();
          if (docs.isEmpty) {
            return const Center(child: Text('No expenses recorded.'));
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final amount = (data['amount'] as num?)?.toDouble() ?? 0;
              final createdAt = _date(data['createdAt']);
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.payments)),
                title: Text(data['title'] as String? ?? 'Expense'),
                subtitle: Text(
                  '${data['category'] ?? 'General'} | ${date.format(createdAt)}',
                ),
                trailing: Text(
                  money.format(amount),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openExpenseSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      ),
    );
  }
}

class _ExpenseSheet extends StatefulWidget {
  final User user;
  const _ExpenseSheet({required this.user});

  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  final _title = TextEditingController();
  final _category = TextEditingController(text: 'General');
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _title.dispose();
    _category.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (_title.text.trim().isEmpty || amount == null) return;
    setState(() => _isSaving = true);
    await FirebaseFirestore.instance.collection('expenses').add({
      'businessId': widget.user.businessId ?? 'default_business',
      'branchId': widget.user.branchId ?? 'main',
      'createdBy': widget.user.id,
      'title': _title.text.trim(),
      'category': _category.text.trim(),
      'amount': amount,
      'notes': _notes.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
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
                      'Add Expense',
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
              _field(_title, 'Expense title'),
              const SizedBox(height: 12),
              _field(_category, 'Category'),
              const SizedBox(height: 12),
              _field(
                _amount,
                'Amount',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 12),
              _field(_notes, 'Notes', required: false),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: const Icon(Icons.save),
                  label: Text(_isSaving ? 'Saving...' : 'Save Expense'),
                ),
              ),
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

DateTime _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

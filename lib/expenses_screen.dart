import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'app_loading_indicator.dart';
import 'package:intl/intl.dart';

import 'models.dart';
import 'business_finance.dart';
import 'notification_inbox_page.dart';

const List<String> _expenseCategories = [
  'General',
  'Rent',
  'Utilities',
  'Transport',
  'Inventory',
  'Salary',
  'Marketing',
  'Maintenance',
  'Taxes',
];

const List<String> _paymentMethods = [
  'Cash',
  'Mobile Money',
  'Bank Transfer',
  'Card',
  'Credit',
];

const List<String> _recurringOptions = [
  'None',
  'Daily',
  'Weekly',
  'Monthly',
  'Yearly',
];

class ExpensesScreen extends StatelessWidget {
  final User user;
  final VoidCallback? onOpenMenu;
  const ExpensesScreen({super.key, required this.user, this.onOpenMenu});

  String get _businessId => user.businessId ?? 'default_business';

  bool _isOwner() => user.role == UserRole.superAdmin;

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

  void _openExpenseSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ExpenseSheet(user: user),
    );
  }

  Future<void> _setValidation({
    required BuildContext context,
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String status,
  }) async {
    await doc.reference.update({
      'validationStatus': status,
      'validatedBy': user.id,
      'validatedAt': FieldValue.serverTimestamp(),
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Expense marked $status.')));
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'sw_TZ',
      symbol: 'Tsh ',
      decimalDigits: 0,
    );

    return StreamBuilder<Map<String, bool>>(
      stream: _permissionsStream,
      builder: (context, permissionSnapshot) {
        final permissions = permissionSnapshot.data ?? {};
        final canValidate =
            _isOwner() || permissions['approve_expenses'] == true;

        return Scaffold(
          appBar: AppBar(
            leading: onOpenMenu == null
                ? null
                : IconButton(
                    tooltip: 'Menu',
                    onPressed: onOpenMenu,
                    icon: const Icon(Icons.menu),
                  ),
            title: const Text('Expense Management'),
            actions: [NotificationBellButton(user: user)],
          ),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('expenses')
                .orderBy('createdAt', descending: true)
                .limit(300)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text('Could not load expenses: ${snapshot.error}'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: ModernLoadingIndicator());
              }

              final docs = snapshot.data!.docs.where((doc) {
                final data = doc.data();
                final businessMatches =
                    (data['businessId'] as String? ?? 'default_business') ==
                    _businessId;
                final branchId = data['branchId'] as String?;
                final branchMatches =
                    user.branchId == null ||
                    branchId == null ||
                    branchId == user.branchId;
                return businessMatches && branchMatches;
              }).toList();

              final analytics = _ExpenseAnalytics.fromDocs(docs);

              return Column(
                children: [
                  _ExpenseAnalyticsPanel(analytics: analytics, money: money),
                  Expanded(
                    child: docs.isEmpty
                        ? const Center(child: Text('No expenses recorded.'))
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 88),
                            itemCount: docs.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              return _ExpenseTile(
                                doc: docs[index],
                                money: money,
                                canValidate: canValidate,
                                onApprove: () => _setValidation(
                                  context: context,
                                  doc: docs[index],
                                  status: 'approved',
                                ),
                                onReject: () => _setValidation(
                                  context: context,
                                  doc: docs[index],
                                  status: 'rejected',
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openExpenseSheet(context),
            icon: const Icon(Icons.add),
            label: const Text('Add Expense'),
          ),
        );
      },
    );
  }
}

class _ExpenseAnalyticsPanel extends StatelessWidget {
  final _ExpenseAnalytics analytics;
  final NumberFormat money;

  const _ExpenseAnalyticsPanel({required this.analytics, required this.money});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
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
              _ExpenseMetricCard(
                title: 'Approved',
                value: money.format(analytics.approvedTotal),
                icon: Icons.verified,
                color: Colors.green,
              ),
              _ExpenseMetricCard(
                title: 'Pending',
                value: money.format(analytics.pendingTotal),
                icon: Icons.pending_actions,
                color: Colors.orange,
              ),
              _ExpenseMetricCard(
                title: 'Rejected',
                value: money.format(analytics.rejectedTotal),
                icon: Icons.block,
                color: Colors.red,
              ),
              _ExpenseMetricCard(
                title: 'Recurring',
                value: analytics.recurringCount.toString(),
                icon: Icons.repeat,
                color: Colors.blue,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ExpenseMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _ExpenseMetricCard({
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

class _ExpenseTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final NumberFormat money;
  final bool canValidate;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ExpenseTile({
    required this.doc,
    required this.money,
    required this.canValidate,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final amount = (data['amount'] as num?)?.toDouble() ?? 0;
    final createdAt = _date(data['createdAt']);
    final date = DateFormat('MMM d, yyyy');
    final status = data['validationStatus'] as String? ?? 'pending';
    final receiptNumber = data['receiptNumber'] as String? ?? 'No receipt';
    final paymentMethod = data['paymentMethod'] as String? ?? 'Cash';
    final recurring = data['recurringFrequency'] as String? ?? 'None';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _statusColor(status).withValues(alpha: 0.16),
        child: Icon(_statusIcon(status), color: _statusColor(status)),
      ),
      title: Text(
        data['title'] as String? ?? 'Expense',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${data['category'] ?? 'General'} | $paymentMethod | Receipt $receiptNumber | ${date.format(createdAt)}${recurring == 'None' ? '' : ' | $recurring'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: SizedBox(
        width: canValidate && status == 'pending' ? 210 : 118,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money.format(amount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    status.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _statusColor(status),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            if (canValidate && status == 'pending') ...[
              IconButton(
                tooltip: 'Approve',
                visualDensity: VisualDensity.compact,
                onPressed: onApprove,
                icon: const Icon(Icons.check_circle, color: Colors.green),
              ),
              IconButton(
                tooltip: 'Reject',
                visualDensity: VisualDensity.compact,
                onPressed: onReject,
                icon: const Icon(Icons.cancel, color: Colors.red),
              ),
            ],
          ],
        ),
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
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _receiptNumber = TextEditingController();
  final _notes = TextEditingController();
  String _category = _expenseCategories.first;
  String _paymentMethod = _paymentMethods.first;
  String _recurringFrequency = _recurringOptions.first;
  String? _selectedBranchId;
  bool _isSaving = false;

  String get _businessId => widget.user.businessId ?? 'default_business';

  @override
  void initState() {
    super.initState();
    _selectedBranchId = widget.user.branchId;
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _receiptNumber.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amount.text.trim());
    final payment = await showBusinessPaymentDialog(
      context,
      businessId: _businessId,
      amount: amount,
      title: 'Pay business expense',
    );
    if (payment == null || !mounted) return;
    setState(() => _isSaving = true);
    final ref = FirebaseFirestore.instance.collection('expenses').doc();
    try {
      await recordBusinessOutflow(
        sourceRef: ref,
        businessId: _businessId,
        payment: payment,
        amount: amount,
        sourceType: 'expense',
        description: _title.text.trim(),
        sourceData: {
          'businessId': _businessId,
          'branchId': _selectedBranchId ?? widget.user.branchId ?? 'main',
          'createdBy': widget.user.id,
          'title': _title.text.trim(),
          'category': _category,
          'amount': amount,
          'receiptNumber': _receiptNumber.text.trim(),
          'paymentMethod': _paymentMethod,
          'recurringFrequency': _recurringFrequency,
          'isRecurring': _recurringFrequency != 'None',
          'notes': _notes.text.trim(),
          'validationStatus': 'pending',
          'validatedBy': null,
          'validatedAt': null,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not record expense: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Record Expense',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _field(_title, 'Expense title'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _categoryDropdown()),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(
                        _amount,
                        'Amount',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        number: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _paymentDropdown()),
                    const SizedBox(width: 10),
                    Expanded(child: _recurringDropdown()),
                  ],
                ),
                const SizedBox(height: 12),
                _branchDropdown(),
                const SizedBox(height: 12),
                _field(_receiptNumber, 'Receipt number'),
                const SizedBox(height: 12),
                _field(_notes, 'Notes', required: false, maxLines: 3),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Validation status: Pending owner approval',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
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
      ),
    );
  }

  Widget _categoryDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _category,
      decoration: const InputDecoration(
        labelText: 'Category',
        border: OutlineInputBorder(),
      ),
      items: _expenseCategories
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: _isSaving
          ? null
          : (value) => setState(() => _category = value!),
    );
  }

  Widget _paymentDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _paymentMethod,
      decoration: const InputDecoration(
        labelText: 'Payment method',
        border: OutlineInputBorder(),
      ),
      items: _paymentMethods
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: _isSaving
          ? null
          : (value) => setState(() => _paymentMethod = value!),
    );
  }

  Widget _recurringDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _recurringFrequency,
      decoration: const InputDecoration(
        labelText: 'Recurring',
        border: OutlineInputBorder(),
      ),
      items: _recurringOptions
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: _isSaving
          ? null
          : (value) => setState(() => _recurringFrequency = value!),
    );
  }

  Widget _branchDropdown() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('branches').snapshots(),
      builder: (context, snapshot) {
        final branches =
            snapshot.data?.docs
                .map((doc) => Branch.fromMap({'id': doc.id, ...doc.data()}))
                .where(
                  (branch) => (branch.businessId ?? _businessId) == _businessId,
                )
                .toList() ??
            const <Branch>[];
        final selected =
            _selectedBranchId != null &&
                branches.any((branch) => branch.id == _selectedBranchId)
            ? _selectedBranchId
            : null;

        return DropdownButtonFormField<String?>(
          initialValue: selected,
          decoration: const InputDecoration(
            labelText: 'Branch / business location',
            border: OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(
                widget.user.branchId == null ? 'Main' : 'Assigned branch',
              ),
            ),
            ...branches.map((branch) {
              return DropdownMenuItem<String?>(
                value: branch.id,
                child: Text(branch.name),
              );
            }),
          ],
          onChanged: _isSaving
              ? null
              : (value) => setState(() => _selectedBranchId = value),
        );
      },
    );
  }
}

Widget _field(
  TextEditingController controller,
  String label, {
  bool required = true,
  bool number = false,
  int maxLines = 1,
  TextInputType? keyboardType,
}) {
  return TextFormField(
    controller: controller,
    maxLines: maxLines,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    validator: (value) {
      if (required && (value == null || value.trim().isEmpty)) {
        return 'Required';
      }
      if (number && double.tryParse(value?.trim() ?? '') == null) {
        return 'Enter a valid number';
      }
      return null;
    },
  );
}

class _ExpenseAnalytics {
  final double approvedTotal;
  final double pendingTotal;
  final double rejectedTotal;
  final int recurringCount;

  const _ExpenseAnalytics({
    required this.approvedTotal,
    required this.pendingTotal,
    required this.rejectedTotal,
    required this.recurringCount,
  });

  factory _ExpenseAnalytics.fromDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var approved = 0.0;
    var pending = 0.0;
    var rejected = 0.0;
    var recurring = 0;

    for (final doc in docs) {
      final data = doc.data();
      final amount = (data['amount'] as num?)?.toDouble() ?? 0;
      final status = data['validationStatus'] as String? ?? 'pending';
      if (status == 'approved') {
        approved += amount;
      } else if (status == 'rejected') {
        rejected += amount;
      } else {
        pending += amount;
      }
      if (data['isRecurring'] == true ||
          (data['recurringFrequency'] as String? ?? 'None') != 'None') {
        recurring++;
      }
    }

    return _ExpenseAnalytics(
      approvedTotal: approved,
      pendingTotal: pending,
      rejectedTotal: rejected,
      recurringCount: recurring,
    );
  }
}

Color _statusColor(String status) {
  if (status == 'approved') return Colors.green;
  if (status == 'rejected') return Colors.red;
  return Colors.orange;
}

IconData _statusIcon(String status) {
  if (status == 'approved') return Icons.verified;
  if (status == 'rejected') return Icons.block;
  return Icons.pending_actions;
}

DateTime _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

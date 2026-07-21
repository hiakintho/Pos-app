import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'app_loading_indicator.dart';
import 'package:intl/intl.dart';

import 'models.dart';
import 'business_finance.dart';

class PayrollPanel extends StatelessWidget {
  final User user;
  const PayrollPanel({super.key, required this.user});

  String get _businessId => user.businessId ?? 'default_business';

  Future<void> _edit(
    BuildContext context, [
    QueryDocumentSnapshot<Map<String, dynamic>>? doc,
  ]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _EmployeeDialog(user: user, employee: doc),
    );
  }

  Future<void> _delete(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete employee?'),
        content: Text(
          'Delete ${doc.data()['name'] ?? 'this employee'}? Payroll history will be retained.',
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
    if (confirmed == true) await doc.reference.delete();
  }

  Future<void> _setStatus(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String status,
  ) => doc.reference.update({
    'status': status,
    'statusUpdatedAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> _extend(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final controller = TextEditingController(
      text: doc.data()['contractEnd']?.toString() ?? '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Extend contract'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'New end date (YYYY-MM-DD)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Extend'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && DateTime.tryParse(value) != null) {
      await doc.reference.update({
        'contractEnd': value,
        'status': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _payOne(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (!_eligible(doc.data())) {
      _message(
        context,
        'This employee is paused, stopped, or outside the contract period.',
      );
      return;
    }
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _PayDialog(defaultAmount: _amount(doc.data()['salary'])),
    );
    if (result == null) return;
    if (!context.mounted) return;
    final month = result['month'] ?? '';
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(month)) {
      _message(context, 'Enter the payroll month as YYYY-MM.');
      return;
    }
    final amount =
        double.tryParse(result['amount'] ?? '') ??
        _amount(doc.data()['salary']);
    if (amount <= 0) {
      _message(context, 'Enter a salary amount greater than zero.');
      return;
    }
    final payment = await showBusinessPaymentDialog(
      context,
      businessId: _businessId,
      amount: amount,
      title: 'Pay employee salary',
    );
    if (payment == null || !context.mounted) return;
    try {
      await _recordPayment(doc, month, amount, payment);
      if (context.mounted) {
        _message(context, '${doc.data()['name']} salary recorded.');
      }
    } catch (e) {
      if (context.mounted) _message(context, e.toString());
    }
  }

  Future<void> _recordPayment(
    QueryDocumentSnapshot<Map<String, dynamic>> employee,
    String month,
    double amount,
    BusinessPaymentSelection payment,
  ) async {
    final ref = FirebaseFirestore.instance
        .collection('payroll_payments')
        .doc('${_businessId}_${month}_${employee.id}');
    await recordBusinessOutflow(
      sourceRef: ref,
      businessId: _businessId,
      payment: payment,
      amount: amount,
      sourceType: 'payroll',
      description: '${employee.data()['name']} salary - $month',
      failIfSourceExists: true,
      sourceData: {
        'businessId': _businessId,
        'branchId': employee.data()['branchId'] ?? user.branchId ?? 'main',
        'employeeId': employee.id,
        'employeeName': employee.data()['name'],
        'payrollMonth': month,
        'amount': amount,
        'paymentAccount': employee.data()['paymentAccount'],
        'paidBy': user.id,
        'paidAt': FieldValue.serverTimestamp(),
        'status': 'paid',
      },
    );
  }

  Future<void> _payAll(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> employees,
  ) async {
    final month = await showDialog<String>(
      context: context,
      builder: (_) => const _MonthDialog(),
    );
    if (month == null) return;
    if (!context.mounted) return;
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(month)) {
      _message(context, 'Enter the payroll month as YYYY-MM.');
      return;
    }
    final eligible = employees
        .where(
          (doc) => _eligible(doc.data()) && _amount(doc.data()['salary']) > 0,
        )
        .toList();
    if (eligible.isEmpty) {
      if (context.mounted) {
        _message(context, 'No active employees with a salary are eligible.');
      }
      return;
    }
    final existing = await FirebaseFirestore.instance
        .collection('payroll_payments')
        .where('businessId', isEqualTo: _businessId)
        .get();
    final paidIds = existing.docs
        .where((doc) => doc.data()['payrollMonth'] == month)
        .map((doc) => doc.data()['employeeId'])
        .toSet();
    final unpaid = eligible.where((doc) => !paidIds.contains(doc.id)).toList();
    if (unpaid.isEmpty) {
      if (context.mounted) {
        _message(
          context,
          'All eligible employees are already paid for $month.',
        );
      }
      return;
    }
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Pay all eligible employees?'),
        content: Text(
          '${unpaid.length} employees will be paid for $month. Paused, stopped, expired, zero-salary, and already-paid employees are excluded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Pay all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    final total = unpaid.fold<double>(
      0,
      (runningTotal, employee) =>
          runningTotal + _amount(employee.data()['salary']),
    );
    final payment = await showBusinessPaymentDialog(
      context,
      businessId: _businessId,
      amount: total,
      title: 'Fund monthly payroll',
    );
    if (payment == null || !context.mounted) return;
    final firestore = FirebaseFirestore.instance;
    final accountRef = firestore
        .collection('business_accounts')
        .doc(payment.accountId);
    final movementRef = firestore.collection('account_transactions').doc();
    await firestore.runTransaction((transaction) async {
      final accountSnapshot = await transaction.get(accountRef);
      if (!accountSnapshot.exists ||
          accountSnapshot.data()?['businessId'] != _businessId) {
        throw Exception('The selected business account no longer exists.');
      }
      final refs = unpaid
          .map(
            (employee) => firestore
                .collection('payroll_payments')
                .doc('${_businessId}_${month}_${employee.id}'),
          )
          .toList();
      for (final ref in refs) {
        if ((await transaction.get(ref)).exists) {
          throw Exception('A salary in this payroll was already recorded.');
        }
      }
      final deduction = total + payment.fee;
      final balance = businessAccountBalance(accountSnapshot.data()!);
      if (balance < deduction) throw Exception('Insufficient account balance.');
      transaction.update(accountRef, {
        'currentBalance': balance - deduction,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      for (var i = 0; i < unpaid.length; i++) {
        final employee = unpaid[i];
        transaction.set(refs[i], {
          'businessId': _businessId,
          'branchId': employee.data()['branchId'] ?? user.branchId ?? 'main',
          'employeeId': employee.id,
          'employeeName': employee.data()['name'],
          'payrollMonth': month,
          'amount': _amount(employee.data()['salary']),
          'paymentAccount': employee.data()['paymentAccount'],
          'businessAccountId': payment.accountId,
          'businessAccountName': payment.accountName,
          'transactionFee': i == 0 ? payment.fee : 0,
          'paidBy': user.id,
          'paidAt': FieldValue.serverTimestamp(),
          'status': 'paid',
        });
      }
      transaction.set(movementRef, {
        'businessId': _businessId,
        'accountId': payment.accountId,
        'accountName': payment.accountName,
        'direction': 'debit',
        'amount': total,
        'transactionFee': payment.fee,
        'total': deduction,
        'sourceType': 'payroll',
        'description': 'Monthly payroll - $month',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
    if (context.mounted) {
      _message(context, '${unpaid.length} salary payments recorded.');
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('employees').snapshots(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: ModernLoadingIndicator());
      }
      final employees =
          snapshot.data!.docs
              .where((doc) => doc.data()['businessId'] == _businessId)
              .toList()
            ..sort(
              (a, b) => (a.data()['name'] ?? '').toString().compareTo(
                (b.data()['name'] ?? '').toString(),
              ),
            );
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () => _edit(context),
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add employee'),
                ),
                OutlinedButton.icon(
                  onPressed: employees.isEmpty
                      ? null
                      : () => _payAll(context, employees),
                  icon: const Icon(Icons.payments),
                  label: const Text('Pay salaries for month'),
                ),
              ],
            ),
          ),
          Expanded(
            child: employees.isEmpty
                ? const Center(child: Text('No employees yet.'))
                : ListView.separated(
                    itemCount: employees.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final doc = employees[index];
                      final data = doc.data();
                      final status = data['status']?.toString() ?? 'active';
                      final employeeName =
                          data['name']?.toString().trim() ?? '';
                      final displayStatus =
                          status == 'active' && !_eligible(data)
                          ? 'contract expired/not started'
                          : status;
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            employeeName.isEmpty
                                ? '?'
                                : employeeName[0].toUpperCase(),
                          ),
                        ),
                        title: Text(
                          employeeName.isEmpty ? 'Employee' : employeeName,
                        ),
                        subtitle: Text(
                          '${data['position'] ?? ''} • ${data['contractType'] ?? ''} • $displayStatus\nContract: ${data['contractStart'] ?? 'Open'} to ${data['contractEnd'] ?? 'Open'} • Pay: ${data['paymentAccount'] ?? 'Not set'}',
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              NumberFormat.currency(
                                locale: 'sw_TZ',
                                symbol: 'Tsh ',
                                decimalDigits: 0,
                              ).format(_amount(data['salary'])),
                            ),
                            IconButton(
                              tooltip: 'Pay employee',
                              onPressed: () => _payOne(context, doc),
                              icon: const Icon(Icons.payments_outlined),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (action) async {
                                switch (action) {
                                  case 'edit':
                                    await _edit(context, doc);
                                  case 'pause':
                                    await _setStatus(doc, 'paused');
                                  case 'activate':
                                    await _setStatus(doc, 'active');
                                  case 'stop':
                                    await _setStatus(doc, 'stopped');
                                  case 'extend':
                                    if (context.mounted) {
                                      await _extend(context, doc);
                                    }
                                  case 'delete':
                                    if (context.mounted) {
                                      await _delete(context, doc);
                                    }
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                                if (status == 'active')
                                  const PopupMenuItem(
                                    value: 'pause',
                                    child: Text('Pause contract'),
                                  ),
                                if (status != 'active' && status != 'stopped')
                                  const PopupMenuItem(
                                    value: 'activate',
                                    child: Text('Resume contract'),
                                  ),
                                const PopupMenuItem(
                                  value: 'extend',
                                  child: Text('Extend contract'),
                                ),
                                if (status != 'stopped')
                                  const PopupMenuItem(
                                    value: 'stop',
                                    child: Text('Stop contract'),
                                  ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    },
  );
}

class _EmployeeDialog extends StatefulWidget {
  final User user;
  final QueryDocumentSnapshot<Map<String, dynamic>>? employee;
  const _EmployeeDialog({required this.user, this.employee});
  @override
  State<_EmployeeDialog> createState() => _EmployeeDialogState();
}

class _EmployeeDialogState extends State<_EmployeeDialog> {
  late final TextEditingController name, position, salary, start, end, account;
  late String contractType, status;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    final data = widget.employee?.data() ?? const <String, dynamic>{};
    name = TextEditingController(text: data['name']?.toString() ?? '');
    position = TextEditingController(text: data['position']?.toString() ?? '');
    salary = TextEditingController(text: data['salary']?.toString() ?? '');
    start = TextEditingController(
      text: data['contractStart']?.toString() ?? '',
    );
    end = TextEditingController(text: data['contractEnd']?.toString() ?? '');
    account = TextEditingController(
      text: data['paymentAccount']?.toString() ?? '',
    );
    contractType = data['contractType']?.toString() ?? 'Permanent';
    status = data['status']?.toString() ?? 'active';
  }

  @override
  void dispose() {
    for (final c in [name, position, salary, start, end, account]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty) return;
    setState(() => saving = true);
    final ref =
        widget.employee?.reference ??
        FirebaseFirestore.instance.collection('employees').doc();
    await ref.set({
      'businessId': widget.user.businessId ?? 'default_business',
      'branchId': widget.user.branchId ?? 'main',
      'name': name.text.trim(),
      'position': position.text.trim(),
      'salary': double.tryParse(salary.text.trim()) ?? 0,
      'contractStart': start.text.trim(),
      'contractEnd': end.text.trim(),
      'paymentAccount': account.text.trim(),
      'contractType': contractType,
      'status': status,
      if (widget.employee == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.employee == null ? 'Add employee' : 'Edit employee'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _input(name, 'Full name'),
            _input(position, 'Position'),
            _input(salary, 'Monthly salary (optional)', number: true),
            DropdownButtonFormField<String>(
              initialValue: contractType,
              decoration: const InputDecoration(labelText: 'Contract type'),
              items: [
                'Permanent',
                'Fixed term',
                'Part time',
                'Casual',
              ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setState(() => contractType = v!),
            ),
            _input(start, 'Contract start (YYYY-MM-DD)'),
            _input(end, 'Contract end (optional)'),
            _input(account, 'Bank/mobile payment account'),
            DropdownButtonFormField<String>(
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'paused', child: Text('Paused')),
                DropdownMenuItem(value: 'stopped', child: Text('Stopped')),
              ],
              onChanged: (v) => setState(() => status = v!),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(saving ? 'Saving...' : 'Save'),
      ),
    ],
  );
}

class _PayDialog extends StatefulWidget {
  final double defaultAmount;
  const _PayDialog({required this.defaultAmount});
  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
  late final TextEditingController month, amount;
  @override
  void initState() {
    super.initState();
    month = TextEditingController(
      text: DateFormat('yyyy-MM').format(DateTime.now()),
    );
    amount = TextEditingController(
      text: widget.defaultAmount > 0
          ? widget.defaultAmount.toStringAsFixed(0)
          : '',
    );
  }

  @override
  void dispose() {
    month.dispose();
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Pay salary'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _input(month, 'Payroll month (YYYY-MM)'),
        _input(amount, 'Amount (optional if salary is set)', number: true),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, {
          'month': month.text.trim(),
          'amount': amount.text.trim(),
        }),
        child: const Text('Record payment'),
      ),
    ],
  );
}

class _MonthDialog extends StatefulWidget {
  const _MonthDialog();
  @override
  State<_MonthDialog> createState() => _MonthDialogState();
}

class _MonthDialogState extends State<_MonthDialog> {
  late final TextEditingController month;
  @override
  void initState() {
    super.initState();
    month = TextEditingController(
      text: DateFormat('yyyy-MM').format(DateTime.now()),
    );
  }

  @override
  void dispose() {
    month.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Monthly payroll'),
    content: _input(month, 'Payroll month (YYYY-MM)'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, month.text.trim()),
        child: const Text('Continue'),
      ),
    ],
  );
}

Widget _input(
  TextEditingController controller,
  String label, {
  bool number = false,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: TextField(
    controller: controller,
    keyboardType: number
        ? const TextInputType.numberWithOptions(decimal: true)
        : null,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  ),
);
double _amount(dynamic value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;
bool _eligible(Map<String, dynamic> data) {
  if ((data['status'] ?? 'active') != 'active') return false;
  final start = DateTime.tryParse(data['contractStart']?.toString() ?? '');
  final end = DateTime.tryParse(data['contractEnd']?.toString() ?? '');
  final now = DateTime.now();
  return (start == null || !now.isBefore(start)) &&
      (end == null || !now.isAfter(end));
}

void _message(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));

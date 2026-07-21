import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class BusinessPaymentSelection {
  final String accountId;
  final String accountName;
  final double fee;

  const BusinessPaymentSelection({
    required this.accountId,
    required this.accountName,
    required this.fee,
  });
}

double businessAccountBalance(Map<String, dynamic> data) =>
    (data['currentBalance'] as num?)?.toDouble() ??
    (data['openingBalance'] as num?)?.toDouble() ??
    0;

Future<void> recordBusinessAccountAdjustment({
  required String accountId,
  required String businessId,
  required double amount,
  required bool deposit,
  required String transactionType,
  required String reason,
  required String createdBy,
  double transactionFee = 0,
}) async {
  if (amount <= 0 || transactionFee < 0) {
    throw Exception('Enter a valid amount and transaction fee.');
  }
  if (deposit && transactionFee > amount) {
    throw Exception('The deposit fee cannot exceed the deposited amount.');
  }
  final firestore = FirebaseFirestore.instance;
  final accountRef = firestore.collection('business_accounts').doc(accountId);
  final movementRef = firestore.collection('account_transactions').doc();
  await firestore.runTransaction((transaction) async {
    final snapshot = await transaction.get(accountRef);
    if (!snapshot.exists || snapshot.data()?['businessId'] != businessId) {
      throw Exception('The selected business account no longer exists.');
    }
    final balance = businessAccountBalance(snapshot.data()!);
    final total = deposit ? amount - transactionFee : amount + transactionFee;
    final newBalance = deposit ? balance + total : balance - total;
    if (newBalance < 0) throw Exception('Insufficient account balance.');
    transaction.update(accountRef, {
      'currentBalance': newBalance,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    transaction.set(movementRef, {
      'businessId': businessId,
      'accountId': accountId,
      'accountName': snapshot.data()?['name'] ?? 'Account',
      'direction': deposit ? 'credit' : 'debit',
      'amount': amount,
      'transactionFee': transactionFee,
      'total': total,
      'transactionType': transactionType,
      'sourceType': transactionType,
      'description': reason,
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
    });
  });
}

Future<BusinessPaymentSelection?> showBusinessPaymentDialog(
  BuildContext context, {
  required String businessId,
  required double amount,
  String title = 'Select payment account',
}) async {
  final snapshot = await FirebaseFirestore.instance
      .collection('business_accounts')
      .where('businessId', isEqualTo: businessId)
      .get();
  if (!context.mounted) return null;
  if (snapshot.docs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Add a business account before making this payment.'),
      ),
    );
    return null;
  }
  return showDialog<BusinessPaymentSelection>(
    context: context,
    builder: (_) => _BusinessPaymentDialog(
      title: title,
      amount: amount,
      accounts: snapshot.docs,
    ),
  );
}

Future<void> recordBusinessOutflow({
  required DocumentReference<Map<String, dynamic>> sourceRef,
  required Map<String, dynamic> sourceData,
  required String businessId,
  required BusinessPaymentSelection payment,
  required double amount,
  required String sourceType,
  required String description,
  bool failIfSourceExists = false,
}) async {
  final firestore = FirebaseFirestore.instance;
  final accountRef = firestore
      .collection('business_accounts')
      .doc(payment.accountId);
  final movementRef = firestore.collection('account_transactions').doc();
  final total = amount + payment.fee;
  await firestore.runTransaction((transaction) async {
    final accountSnapshot = await transaction.get(accountRef);
    if (failIfSourceExists && (await transaction.get(sourceRef)).exists) {
      throw Exception('This payment has already been recorded.');
    }
    if (!accountSnapshot.exists ||
        accountSnapshot.data()?['businessId'] != businessId) {
      throw Exception('The selected business account no longer exists.');
    }
    final balance = businessAccountBalance(accountSnapshot.data()!);
    if (balance < total) {
      throw Exception(
        'Insufficient account balance. Available: ${NumberFormat.currency(locale: 'sw_TZ', symbol: 'Tsh ', decimalDigits: 0).format(balance)}.',
      );
    }
    transaction.update(accountRef, {
      'currentBalance': balance - total,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    transaction.set(sourceRef, {
      ...sourceData,
      'businessAccountId': payment.accountId,
      'businessAccountName': payment.accountName,
      'transactionFee': payment.fee,
      'totalAccountDeduction': total,
    });
    transaction.set(movementRef, {
      'businessId': businessId,
      'accountId': payment.accountId,
      'accountName': payment.accountName,
      'direction': 'debit',
      'amount': amount,
      'transactionFee': payment.fee,
      'total': total,
      'sourceType': sourceType,
      'sourceId': sourceRef.id,
      'description': description,
      'createdAt': FieldValue.serverTimestamp(),
    });
  });
}

class _BusinessPaymentDialog extends StatefulWidget {
  final String title;
  final double amount;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> accounts;
  const _BusinessPaymentDialog({
    required this.title,
    required this.amount,
    required this.accounts,
  });

  @override
  State<_BusinessPaymentDialog> createState() => _BusinessPaymentDialogState();
}

class _BusinessPaymentDialogState extends State<_BusinessPaymentDialog> {
  late String accountId = widget.accounts.first.id;
  final fee = TextEditingController();

  @override
  void dispose() {
    fee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.accounts.firstWhere((doc) => doc.id == accountId);
    final feeValue = double.tryParse(fee.text.trim()) ?? 0;
    final money = NumberFormat.currency(
      locale: 'sw_TZ',
      symbol: 'Tsh ',
      decimalDigits: 0,
    );
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: accountId,
              decoration: const InputDecoration(
                labelText: 'Deduct from business account',
                border: OutlineInputBorder(),
              ),
              items: widget.accounts.map((doc) {
                final data = doc.data();
                return DropdownMenuItem(
                  value: doc.id,
                  child: Text(
                    '${data['name'] ?? 'Account'} — ${money.format(businessAccountBalance(data))}',
                  ),
                );
              }).toList(),
              onChanged: (value) => setState(() => accountId = value!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: fee,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Transaction/bank fee (optional)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Payment: ${money.format(widget.amount)}\nTotal deduction: ${money.format(widget.amount + feeValue)}',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              feeValue < 0 ||
                  businessAccountBalance(selected.data()) <
                      widget.amount + feeValue
              ? null
              : () => Navigator.pop(
                  context,
                  BusinessPaymentSelection(
                    accountId: selected.id,
                    accountName:
                        selected.data()['name']?.toString() ?? 'Account',
                    fee: feeValue,
                  ),
                ),
          child: const Text('Confirm payment'),
        ),
      ],
    );
  }
}

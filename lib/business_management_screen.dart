import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'models.dart';
import 'notification_inbox_page.dart';

class BusinessManagementScreen extends StatelessWidget {
  final User user;
  final VoidCallback? onOpenMenu;
  const BusinessManagementScreen({
    super.key,
    required this.user,
    this.onOpenMenu,
  });

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 5,
    child: Scaffold(
      appBar: AppBar(
        leading: onOpenMenu == null
            ? null
            : IconButton(onPressed: onOpenMenu, icon: const Icon(Icons.menu)),
        title: const Text('Business Management'),
        actions: [NotificationBellButton(user: user)],
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(icon: Icon(Icons.account_balance), text: 'Accounting'),
            Tab(icon: Icon(Icons.wallet), text: 'Accounts'),
            Tab(icon: Icon(Icons.badge), text: 'Employees'),
            Tab(icon: Icon(Icons.precision_manufacturing), text: 'Assets'),
            Tab(icon: Icon(Icons.swap_horiz), text: 'Stock Transfers'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          _AccountingTab(user: user),
          _AccountsTab(user: user),
          _EmployeesTab(user: user),
          _AssetsTab(user: user),
          _TransfersTab(user: user),
        ],
      ),
    ),
  );
}

String _businessId(User user) => user.businessId ?? 'default_business';
double _number(dynamic value) => (value as num?)?.toDouble() ?? 0;
DateTime _date(dynamic value) => value is Timestamp
    ? value.toDate()
    : DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
final _money = NumberFormat.currency(
  locale: 'sw_TZ',
  symbol: 'Tsh ',
  decimalDigits: 0,
);

Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _businessDocs(
  String collection,
  User user,
) => FirebaseFirestore.instance.collection(collection).snapshots().map((
  snapshot,
) {
  final docs = snapshot.docs
      .where((doc) => doc.data()['businessId'] == _businessId(user))
      .toList();
  docs.sort(
    (a, b) =>
        _date(b.data()['createdAt']).compareTo(_date(a.data()['createdAt'])),
  );
  return docs;
});

class _AccountingTab extends StatelessWidget {
  final User user;
  const _AccountingTab({required this.user});

  Future<void> _add(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _AccountingEntryDialog(),
    );
    if (result == null) return;
    await FirebaseFirestore.instance.collection('accounting_entries').add({
      ...result,
      'businessId': _businessId(user),
      'branchId': user.branchId ?? 'main',
      'createdBy': user.id,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: _businessDocs('accounting_entries', user),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final entries = snapshot.data!;
      final income = entries
          .where((doc) => doc.data()['type'] == 'income')
          .fold<double>(
            0,
            (total, doc) => total + _number(doc.data()['amount']),
          );
      final expenses = entries
          .where((doc) => doc.data()['type'] == 'expense')
          .fold<double>(
            0,
            (total, doc) => total + _number(doc.data()['amount']),
          );
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SummaryCard('Income', _money.format(income), Colors.green),
              _SummaryCard('Expenses', _money.format(expenses), Colors.red),
              _SummaryCard(
                'Net Profit / Loss',
                _money.format(income - expenses),
                income >= expenses ? Colors.teal : Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _add(context),
            icon: const Icon(Icons.add),
            label: const Text('Record accounting entry'),
          ),
          const SizedBox(height: 12),
          ...entries.map((doc) {
            final data = doc.data();
            final incomeEntry = data['type'] == 'income';
            return Card(
              child: ListTile(
                leading: Icon(
                  incomeEntry ? Icons.south_west : Icons.north_east,
                  color: incomeEntry ? Colors.green : Colors.red,
                ),
                title: Text(data['description'] ?? data['category'] ?? 'Entry'),
                subtitle: Text(
                  '${data['category'] ?? 'General'} • ${DateFormat.yMMMd().format(_date(data['createdAt']))}',
                ),
                trailing: Text(
                  '${incomeEntry ? '+' : '-'}${_money.format(_number(data['amount']))}',
                ),
              ),
            );
          }),
        ],
      );
    },
  );
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SummaryCard(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 250,
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

class _AccountingEntryDialog extends StatefulWidget {
  const _AccountingEntryDialog();
  @override
  State<_AccountingEntryDialog> createState() => _AccountingEntryDialogState();
}

class _AccountingEntryDialogState extends State<_AccountingEntryDialog> {
  String type = 'income';
  final category = TextEditingController();
  final description = TextEditingController();
  final amount = TextEditingController();
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Accounting entry'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField(
            initialValue: type,
            items: const [
              DropdownMenuItem(value: 'income', child: Text('Income')),
              DropdownMenuItem(value: 'expense', child: Text('Expense')),
            ],
            onChanged: (value) => setState(() => type = value!),
          ),
          TextField(
            controller: category,
            decoration: const InputDecoration(labelText: 'Account/category'),
          ),
          TextField(
            controller: description,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Amount'),
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
        onPressed: () {
          final value = double.tryParse(amount.text);
          if (value == null || value <= 0) return;
          Navigator.pop(context, {
            'type': type,
            'category': category.text.trim(),
            'description': description.text.trim(),
            'amount': value,
          });
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class _AccountsTab extends StatelessWidget {
  final User user;
  const _AccountsTab({required this.user});
  Future<void> _add(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _SimpleRecordDialog(
        title: 'Financial account',
        fields: [
          'Account name',
          'Bank/provider',
          'Account/phone number',
          'Opening balance',
        ],
        types: ['Bank account', 'Mobile money', 'Cash account'],
      ),
    );
    if (result == null) return;
    await FirebaseFirestore.instance.collection('business_accounts').add({
      'businessId': _businessId(user),
      'type': result['type'],
      'name': result['values'][0],
      'provider': result['values'][1],
      'accountNumber': result['values'][2],
      'openingBalance': double.tryParse(result['values'][3]) ?? 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) => _RecordList(
    stream: _businessDocs('business_accounts', user),
    addLabel: 'Add bank or mobile-money account',
    onAdd: () => _add(context),
    builder: (data) => ListTile(
      leading: Icon(
        data['type'] == 'Mobile money'
            ? Icons.phone_android
            : Icons.account_balance,
      ),
      title: Text(data['name'] ?? 'Financial account'),
      subtitle: Text(
        '${data['provider'] ?? ''} • ${data['accountNumber'] ?? ''}',
      ),
      trailing: Text(_money.format(_number(data['openingBalance']))),
    ),
  );
}

class _EmployeesTab extends StatelessWidget {
  final User user;
  const _EmployeesTab({required this.user});
  Future<void> _add(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _SimpleRecordDialog(
        title: 'Employee contract and salary',
        fields: [
          'Full name',
          'Position',
          'Monthly salary',
          'Contract start (YYYY-MM-DD)',
          'Contract end (YYYY-MM-DD)',
          'Bank/mobile account',
        ],
        types: ['Permanent', 'Fixed term', 'Part time', 'Casual'],
      ),
    );
    if (result == null) return;
    final values = result['values'] as List<String>;
    await FirebaseFirestore.instance.collection('employees').add({
      'businessId': _businessId(user),
      'branchId': user.branchId ?? 'main',
      'contractType': result['type'],
      'name': values[0],
      'position': values[1],
      'salary': double.tryParse(values[2]) ?? 0,
      'contractStart': values[3],
      'contractEnd': values[4],
      'paymentAccount': values[5],
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) => _RecordList(
    stream: _businessDocs('employees', user),
    addLabel: 'Add employee and contract',
    onAdd: () => _add(context),
    builder: (data) => ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person)),
      title: Text(data['name'] ?? 'Employee'),
      subtitle: Text(
        '${data['position'] ?? ''} • ${data['contractType'] ?? ''}\nPay to: ${data['paymentAccount'] ?? 'Not set'}',
      ),
      isThreeLine: true,
      trailing: Text(_money.format(_number(data['salary']))),
    ),
  );
}

class _AssetsTab extends StatelessWidget {
  final User user;
  const _AssetsTab({required this.user});
  Future<void> _add(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _SimpleRecordDialog(
        title: 'Asset or equipment',
        fields: [
          'Asset name',
          'Category',
          'Purchase/current value',
          'Serial number',
          'Branch ID/location',
        ],
        types: [
          'Equipment',
          'Vehicle',
          'Furniture',
          'Building',
          'Technology',
          'Other',
        ],
      ),
    );
    if (result == null) return;
    final values = result['values'] as List<String>;
    await FirebaseFirestore.instance.collection('business_assets').add({
      'businessId': _businessId(user),
      'assetType': result['type'],
      'name': values[0],
      'category': values[1],
      'value': double.tryParse(values[2]) ?? 0,
      'serialNumber': values[3],
      'branchId': values[4].isEmpty ? user.branchId ?? 'main' : values[4],
      'condition': 'good',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) => _RecordList(
    stream: _businessDocs('business_assets', user),
    addLabel: 'Register asset or equipment',
    onAdd: () => _add(context),
    builder: (data) => ListTile(
      leading: const Icon(Icons.precision_manufacturing),
      title: Text(data['name'] ?? 'Asset'),
      subtitle: Text(
        '${data['assetType'] ?? ''} • Branch ${data['branchId'] ?? 'main'} • ${data['condition'] ?? 'good'}',
      ),
      trailing: Text(_money.format(_number(data['value']))),
    ),
  );
}

class _RecordList extends StatelessWidget {
  final Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> stream;
  final String addLabel;
  final VoidCallback onAdd;
  final Widget Function(Map<String, dynamic>) builder;
  const _RecordList({
    required this.stream,
    required this.addLabel,
    required this.onAdd,
    required this.builder,
  });
  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: stream,
    builder: (context, snapshot) {
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(addLabel),
          ),
          const SizedBox(height: 12),
          ...snapshot.data!.map((doc) => Card(child: builder(doc.data()))),
        ],
      );
    },
  );
}

class _SimpleRecordDialog extends StatefulWidget {
  final String title;
  final List<String> fields;
  final List<String> types;
  const _SimpleRecordDialog({
    required this.title,
    required this.fields,
    required this.types,
  });
  @override
  State<_SimpleRecordDialog> createState() => _SimpleRecordDialogState();
}

class _SimpleRecordDialogState extends State<_SimpleRecordDialog> {
  late String type = widget.types.first;
  late final controllers = widget.fields
      .map((_) => TextEditingController())
      .toList();
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField(
              initialValue: type,
              items: widget.types
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => type = value!),
            ),
            for (var i = 0; i < widget.fields.length; i++)
              TextField(
                controller: controllers[i],
                decoration: InputDecoration(labelText: widget.fields[i]),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, {
          'type': type,
          'values': controllers.map((item) => item.text.trim()).toList(),
        }),
        child: const Text('Save'),
      ),
    ],
  );
}

class _TransfersTab extends StatelessWidget {
  final User user;
  const _TransfersTab({required this.user});

  Future<void> _create(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CreateTransferDialog(user: user),
    );
    if (result == null) return;
    await FirebaseFirestore.instance.collection('stock_transfers').add({
      ...result,
      'businessId': _businessId(user),
      'senderId': user.id,
      'senderName': user.name,
      'status': 'in_transit',
      'statusHistory': [
        {'status': 'in_transit', 'at': Timestamp.now(), 'by': user.id},
      ],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _receive(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> transfer,
  ) async {
    final result = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => _ReceiveTransferDialog(
        transferId: transfer.id,
        items: List<Map<String, dynamic>>.from(
          transfer.data()['items'] ?? const [],
        ),
      ),
    );
    if (result == null) return;
    await transfer.reference.update({
      'receivedItems': result,
      'status': 'received_pending_sender_confirmation',
      'receivedBy': user.id,
      'receivedByName': user.name,
      'receivedAt': FieldValue.serverTimestamp(),
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': 'received_pending_sender_confirmation',
          'at': Timestamp.now(),
          'by': user.id,
        },
      ]),
    });
  }

  Future<void> _confirm(
    QueryDocumentSnapshot<Map<String, dynamic>> transfer,
  ) async {
    final firestore = FirebaseFirestore.instance;
    await firestore.runTransaction((transaction) async {
      final data = transfer.data();
      final sent = List<Map<String, dynamic>>.from(data['items'] ?? const []);
      final received = List<Map<String, dynamic>>.from(
        data['receivedItems'] ?? const [],
      );
      final snapshots = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      final destinationSnapshots =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final item in sent) {
        final productId = item['productId'].toString();
        snapshots[productId] = await transaction.get(
          firestore.collection('products').doc(productId),
        );
        final destinationId = '${data['toBranchId']}_$productId';
        destinationSnapshots[productId] = await transaction.get(
          firestore.collection('products').doc(destinationId),
        );
      }
      for (var i = 0; i < sent.length; i++) {
        final item = sent[i];
        final productId = item['productId'].toString();
        final source = snapshots[productId]!;
        final sourceData = source.data()!;
        final sentQuantity = _number(item['quantity']);
        final receivedQuantity = i < received.length
            ? _number(received[i]['receivedQuantity'])
            : 0;
        final available = _number(sourceData['stockQuantity']);
        if (available < sentQuantity)
          throw Exception('Not enough stock for ${item['name']}');
        transaction.update(source.reference, {
          'stockQuantity': available - sentQuantity,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        final destination = destinationSnapshots[productId]!;
        if (destination.exists) {
          transaction.update(destination.reference, {
            'stockQuantity':
                _number(destination.data()?['stockQuantity']) +
                receivedQuantity,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          transaction.set(destination.reference, {
            ...sourceData,
            'id': destination.reference.id,
            'sourceProductId': productId,
            'branchId': data['toBranchId'],
            'stockQuantity': receivedQuantity,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
      transaction.update(transfer.reference, {
        'status': 'completed',
        'confirmedBySender': user.id,
        'confirmedAt': FieldValue.serverTimestamp(),
        'statusHistory': FieldValue.arrayUnion([
          {'status': 'completed', 'at': Timestamp.now(), 'by': user.id},
        ]),
      });
    });
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: _businessDocs('stock_transfers', user),
    builder: (context, snapshot) {
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: () => _create(context),
            icon: const Icon(Icons.local_shipping),
            label: const Text('Create branch stock transfer'),
          ),
          const SizedBox(height: 12),
          ...snapshot.data!.map((transfer) {
            final data = transfer.data();
            final items = List<Map<String, dynamic>>.from(
              data['items'] ?? const [],
            );
            final status = data['status'] ?? 'in_transit';
            final canReceive =
                status == 'in_transit' &&
                (user.branchId == null || user.branchId == data['toBranchId']);
            final canConfirm =
                status == 'received_pending_sender_confirmation' &&
                (user.role == UserRole.superAdmin ||
                    user.branchId == data['fromBranchId']);
            return Card(
              child: ExpansionTile(
                leading: const Icon(Icons.swap_horiz),
                title: Text(
                  '${data['fromBranchName'] ?? data['fromBranchId']} → ${data['toBranchName'] ?? data['toBranchId']}',
                ),
                subtitle: Text(status.toString().replaceAll('_', ' ')),
                children: [
                  ...items.map(
                    (item) => ListTile(
                      title: Text(item['name'] ?? 'Product'),
                      trailing: Text('${item['quantity']} sent'),
                    ),
                  ),
                  if (canReceive)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: FilledButton.icon(
                        onPressed: () => _receive(context, transfer),
                        icon: const Icon(Icons.inventory),
                        label: const Text('Record received items'),
                      ),
                    ),
                  if (canConfirm)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: FilledButton.icon(
                        onPressed: () => _confirm(transfer),
                        icon: const Icon(Icons.verified),
                        label: const Text('Sender confirms delivery'),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      );
    },
  );
}

class _CreateTransferDialog extends StatefulWidget {
  final User user;
  const _CreateTransferDialog({required this.user});
  @override
  State<_CreateTransferDialog> createState() => _CreateTransferDialogState();
}

class _CreateTransferDialogState extends State<_CreateTransferDialog> {
  String? fromBranch;
  String? toBranch;
  final quantities = <String, TextEditingController>{};
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New stock transfer'),
    content: SizedBox(
      width: 620,
      height: 520,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('branches').snapshots(),
        builder: (context, branchSnapshot) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('products')
                .snapshots(),
            builder: (context, productSnapshot) {
              if (!branchSnapshot.hasData || !productSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final branches = branchSnapshot.data!.docs
                  .where(
                    (doc) =>
                        (doc.data()['businessId'] ?? 'default_business') ==
                        _businessId(widget.user),
                  )
                  .toList();
              final products = productSnapshot.data!.docs.where((doc) {
                final data = doc.data();
                return (data['businessId'] ?? 'default_business') ==
                        _businessId(widget.user) &&
                    (fromBranch == null ||
                        (data['branchId'] ?? 'main') == fromBranch);
              }).toList();
              return Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: fromBranch,
                    decoration: const InputDecoration(
                      labelText: 'Sending branch',
                    ),
                    items: branches
                        .map(
                          (doc) => DropdownMenuItem(
                            value: doc.id,
                            child: Text(doc.data()['name'] ?? doc.id),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() {
                      fromBranch = value;
                      quantities.clear();
                    }),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: toBranch,
                    decoration: const InputDecoration(
                      labelText: 'Receiving branch',
                    ),
                    items: branches
                        .map(
                          (doc) => DropdownMenuItem(
                            value: doc.id,
                            child: Text(doc.data()['name'] ?? doc.id),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => toBranch = value),
                  ),
                  const SizedBox(height: 8),
                  const Text('Enter quantities for every product being sent.'),
                  Expanded(
                    child: ListView(
                      children: products.map((doc) {
                        final data = doc.data();
                        final controller = quantities.putIfAbsent(
                          doc.id,
                          () => TextEditingController(),
                        );
                        return ListTile(
                          title: Text(data['name'] ?? 'Product'),
                          subtitle: Text(
                            '${_number(data['stockQuantity']).toStringAsFixed(0)} available',
                          ),
                          trailing: SizedBox(
                            width: 100,
                            child: TextField(
                              controller: controller,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Send',
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  FilledButton(
                    onPressed:
                        fromBranch == null ||
                            toBranch == null ||
                            fromBranch == toBranch
                        ? null
                        : () {
                            final items = products
                                .map((doc) {
                                  final quantity =
                                      double.tryParse(
                                        quantities[doc.id]?.text ?? '',
                                      ) ??
                                      0;
                                  final available = _number(
                                    doc.data()['stockQuantity'],
                                  );
                                  return quantity <= 0 || quantity > available
                                      ? null
                                      : <String, dynamic>{
                                          'productId': doc.id,
                                          'name': doc.data()['name'],
                                          'quantity': quantity,
                                        };
                                })
                                .whereType<Map<String, dynamic>>()
                                .toList();
                            if (items.isEmpty) return;
                            String name(String? id) =>
                                branches
                                    .where((doc) => doc.id == id)
                                    .map((doc) => doc.data()['name'].toString())
                                    .firstOrNull ??
                                id ??
                                '';
                            Navigator.pop(context, {
                              'fromBranchId': fromBranch,
                              'fromBranchName': name(fromBranch),
                              'toBranchId': toBranch,
                              'toBranchName': name(toBranch),
                              'items': items,
                            });
                          },
                    child: const Text('Dispatch transfer'),
                  ),
                ],
              );
            },
          );
        },
      ),
    ),
  );
}

class _ReceiveTransferDialog extends StatefulWidget {
  final String transferId;
  final List<Map<String, dynamic>> items;
  const _ReceiveTransferDialog({required this.transferId, required this.items});
  @override
  State<_ReceiveTransferDialog> createState() => _ReceiveTransferDialogState();
}

class _ReceiveTransferDialogState extends State<_ReceiveTransferDialog> {
  late final quantities = widget.items
      .map(
        (item) => TextEditingController(
          text: _number(item['quantity']).toStringAsFixed(0),
        ),
      )
      .toList();
  late final photos = List<XFile?>.filled(widget.items.length, null);
  bool saving = false;
  Future<void> _save() async {
    setState(() => saving = true);
    final received = <Map<String, dynamic>>[];
    for (var i = 0; i < widget.items.length; i++) {
      String? photoUrl;
      final photo = photos[i];
      if (photo != null) {
        final Uint8List bytes = await photo.readAsBytes();
        final ref = FirebaseStorage.instance.ref(
          'stock_transfers/${widget.transferId}/${widget.items[i]['productId']}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
        photoUrl = await ref.getDownloadURL();
      }
      received.add({
        ...widget.items[i],
        'receivedQuantity': double.tryParse(quantities[i].text) ?? 0,
        'photoUrl': photoUrl,
      });
    }
    if (mounted) Navigator.pop(context, received);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Receive transfer item by item'),
    content: SizedBox(
      width: 560,
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: widget.items.length,
        itemBuilder: (context, i) => Card(
          child: ListTile(
            title: Text(widget.items[i]['name'] ?? 'Product'),
            subtitle: Text('Sent: ${widget.items[i]['quantity']}'),
            trailing: SizedBox(
              width: 210,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: quantities[i],
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Received'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Attach optional photo',
                    onPressed: () async {
                      final image = await ImagePicker().pickImage(
                        source: ImageSource.camera,
                        imageQuality: 70,
                      );
                      if (image != null) setState(() => photos[i] = image);
                    },
                    icon: Icon(
                      photos[i] == null
                          ? Icons.add_a_photo
                          : Icons.check_circle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving ? null : _save,
        child: Text(saving ? 'Saving...' : 'Submit received items'),
      ),
    ],
  );
}

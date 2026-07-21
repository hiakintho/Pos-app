import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models.dart';
import 'business_finance.dart';
import 'notification_inbox_page.dart';

class PurchasesScreen extends StatefulWidget {
  final User user;
  final VoidCallback? onOpenMenu;
  const PurchasesScreen({super.key, required this.user, this.onOpenMenu});

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  String get _businessId => widget.user.businessId ?? 'default_business';
  bool get _isOwner => widget.user.role == UserRole.superAdmin;

  Stream<Map<String, bool>> get _permissionsStream {
    final roleDocId = '${_businessId}_${widget.user.role}';
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
              .doc(widget.user.role)
              .snapshots();
        })
        .map((doc) => Map<String, bool>.from(doc.data()?['permissions'] ?? {}));
  }

  bool _can(Map<String, bool> permissions, String featureId) {
    if (_isOwner) return true;
    if (permissions.isEmpty) return true;
    return permissions[featureId] == true;
  }

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
      builder: (context) => _PurchaseOrderSheet(user: widget.user),
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

    return StreamBuilder<Map<String, bool>>(
      stream: _permissionsStream,
      builder: (context, permissionSnapshot) {
        final permissions = permissionSnapshot.data ?? {};
        final canManage = _can(permissions, 'manage_purchase_orders');
        final canApprove = _can(permissions, 'approve_purchases');
        final canReceive = _can(permissions, 'receive_goods');
        final canVerifyInvoice = _can(permissions, 'verify_purchase_invoices');
        final canViewBranches = _can(permissions, 'branch_purchase_reports');

        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              leading: widget.onOpenMenu == null
                  ? null
                  : IconButton(
                      tooltip: 'Menu',
                      onPressed: widget.onOpenMenu,
                      icon: const Icon(Icons.menu),
                    ),
              title: const Text('Purchase Management'),
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Analytics'),
                  Tab(text: 'Orders'),
                  Tab(text: 'Suppliers'),
                  Tab(text: 'Adjustments'),
                ],
              ),
              actions: [
                NotificationBellButton(user: widget.user),
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
                if (canManage)
                  IconButton(
                    tooltip: 'Create purchase order',
                    onPressed: _openPurchaseSheet,
                    icon: const Icon(Icons.add_shopping_cart),
                  ),
              ],
            ),
            body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('purchase_orders')
                  .orderBy('createdAt', descending: true)
                  .limit(400)
                  .snapshots(),
              builder: (context, purchaseSnapshot) {
                final orders =
                    purchaseSnapshot.data?.docs.where((doc) {
                      final data = doc.data();
                      final businessMatch =
                          (data['businessId'] as String? ??
                              'default_business') ==
                          _businessId;
                      final branchMatch =
                          canViewBranches ||
                          widget.user.branchId == null ||
                          (data['branchId'] as String? ?? 'main') ==
                              widget.user.branchId;
                      return businessMatch && branchMatch;
                    }).toList() ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                return TabBarView(
                  children: [
                    _PurchaseAnalyticsTab(orders: orders, money: money),
                    _PurchaseOrdersTab(
                      orders: orders,
                      money: money,
                      date: date,
                      canApprove: canApprove,
                      canReceive: canReceive,
                      canVerifyInvoice: canVerifyInvoice,
                    ),
                    _SuppliersTab(businessId: _businessId),
                    _AdjustmentsTab(businessId: _businessId, date: date),
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

class _PurchaseAnalyticsTab extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> orders;
  final NumberFormat money;

  const _PurchaseAnalyticsTab({required this.orders, required this.money});

  @override
  Widget build(BuildContext context) {
    final analytics = _PurchaseAnalytics.fromDocs(orders);
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
                  title: 'Purchase Cost',
                  value: money.format(analytics.totalCost),
                  icon: Icons.shopping_bag,
                  color: Colors.green,
                ),
                _MetricCard(
                  title: 'Pending Approval',
                  value: analytics.pendingApproval.toString(),
                  icon: Icons.approval,
                  color: Colors.orange,
                ),
                _MetricCard(
                  title: 'Unpaid Balance',
                  value: money.format(analytics.unpaidBalance),
                  icon: Icons.schedule,
                  color: Colors.red,
                ),
                _MetricCard(
                  title: 'Received Goods',
                  value: analytics.receivedQuantity.toStringAsFixed(0),
                  icon: Icons.inventory_2,
                  color: Colors.blue,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _BreakdownCard(
          title: 'Branch-wise Purchases',
          rows: analytics.branchTotals.entries
              .map(
                (entry) => _BreakdownRow(entry.key, money.format(entry.value)),
              )
              .toList(),
          emptyMessage: 'No branch purchase data yet.',
        ),
        const SizedBox(height: 12),
        _BreakdownCard(
          title: 'Payment Status',
          rows: analytics.paymentTotals.entries
              .map(
                (entry) => _BreakdownRow(entry.key, money.format(entry.value)),
              )
              .toList(),
          emptyMessage: 'No payment data yet.',
        ),
      ],
    );
  }
}

class _PurchaseOrdersTab extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> orders;
  final NumberFormat money;
  final DateFormat date;
  final bool canApprove;
  final bool canReceive;
  final bool canVerifyInvoice;

  const _PurchaseOrdersTab({
    required this.orders,
    required this.money,
    required this.date,
    required this.canApprove,
    required this.canReceive,
    required this.canVerifyInvoice,
  });

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const Center(child: Text('No purchase orders yet.'));
    }
    return ListView.separated(
      itemCount: orders.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final doc = orders[index];
        final data = doc.data();
        final total = (data['totalAmount'] as num?)?.toDouble() ?? 0;
        final approval = data['approvalStatus'] as String? ?? 'pending';
        final receiving = data['receivingStatus'] as String? ?? 'ordered';
        final invoice = data['invoiceStatus'] as String? ?? 'unverified';
        final payment = data['paymentStatus'] as String? ?? 'unpaid';
        return ListTile(
          leading: CircleAvatar(
            child: Icon(
              receiving == 'received' ? Icons.inventory_2 : Icons.shopping_bag,
            ),
          ),
          title: Text(data['supplierName'] as String? ?? 'Supplier'),
          subtitle: Text(
            '${data['productName'] ?? 'Goods'} | $approval | $receiving | Invoice $invoice | $payment | ${date.format(_date(data['createdAt']))}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: SizedBox(
            width: 250,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    money.format(total),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (canApprove && approval == 'pending')
                  IconButton(
                    tooltip: 'Approve',
                    onPressed: () => doc.reference.update({
                      'approvalStatus': 'approved',
                      'approvedAt': FieldValue.serverTimestamp(),
                    }),
                    icon: const Icon(Icons.verified, color: Colors.green),
                  ),
                if (canVerifyInvoice && invoice != 'verified')
                  IconButton(
                    tooltip: 'Verify invoice',
                    onPressed: () => doc.reference.update({
                      'invoiceStatus': 'verified',
                      'invoiceVerifiedAt': FieldValue.serverTimestamp(),
                    }),
                    icon: const Icon(Icons.fact_check),
                  ),
                if (canReceive && receiving != 'received')
                  IconButton(
                    tooltip: 'Receive goods',
                    onPressed: () => _receiveGoods(doc),
                    icon: const Icon(Icons.download_done),
                  ),
                if ((data['invoiceAttachmentUrl'] as String? ?? '').isNotEmpty)
                  IconButton(
                    tooltip: 'Open invoice attachment',
                    onPressed: () => launchUrl(
                      Uri.parse(data['invoiceAttachmentUrl'] as String),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.receipt_long),
                  ),
                if ((data['deliveryNoteAttachmentUrl'] as String? ?? '')
                    .isNotEmpty)
                  IconButton(
                    tooltip: 'Open delivery note',
                    onPressed: () => launchUrl(
                      Uri.parse(data['deliveryNoteAttachmentUrl'] as String),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.description_outlined),
                  ),
                PopupMenuButton<String>(
                  tooltip: 'Payment status',
                  onSelected: (value) => doc.reference.update({
                    'paymentStatus': value,
                    'updatedAt': FieldValue.serverTimestamp(),
                  }),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'unpaid', child: Text('Unpaid')),
                    PopupMenuItem(value: 'partial', child: Text('Partial')),
                    PopupMenuItem(value: 'paid', child: Text('Paid')),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _receiveGoods(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final productId = data['productId'] as String?;
    final quantity = (data['quantity'] as num?)?.toDouble() ?? 0;
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    if (productId != null && productId.isNotEmpty && quantity > 0) {
      batch.update(firestore.collection('products').doc(productId), {
        'stockQuantity': FieldValue.increment(quantity),
        'lastPurchasedAt': FieldValue.serverTimestamp(),
        if (data['unitCost'] != null) 'productCost': data['unitCost'],
      });
    }
    batch.update(doc.reference, {
      'receivingStatus': 'received',
      'receivedQuantity': quantity,
      'receivedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(firestore.collection('stock_purchases').doc(), {
      'businessId': data['businessId'],
      'branchId': data['branchId'],
      'productId': productId,
      'productName': data['productName'],
      'supplierName': data['supplierName'],
      'quantity': quantity,
      'unitCost': data['unitCost'],
      'totalAmount': data['totalAmount'],
      'purchaseOrderId': doc.id,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}

class _SuppliersTab extends StatelessWidget {
  final String businessId;
  const _SuppliersTab({required this.businessId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('suppliers')
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
        if (docs.isEmpty) return const Center(child: Text('No suppliers yet.'));
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final data = docs[index].data();
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.local_shipping)),
              title: Text(data['name'] as String? ?? 'Supplier'),
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

class _AdjustmentsTab extends StatelessWidget {
  final String businessId;
  final DateFormat date;

  const _AdjustmentsTab({required this.businessId, required this.date});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('stock_adjustments')
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
          return const Center(child: Text('No stock adjustments yet.'));
        }
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final data = docs[index].data();
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.tune)),
              title: Text(data['productName'] as String? ?? 'Product'),
              subtitle: Text(
                '${data['reason'] ?? 'Adjustment'} | ${date.format(_date(data['createdAt']))}',
              ),
              trailing: Text(
                (data['quantity'] as num?)?.toDouble().toStringAsFixed(0) ??
                    '0',
              ),
            );
          },
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

class _PurchaseOrderSheet extends StatefulWidget {
  final User user;
  const _PurchaseOrderSheet({required this.user});

  @override
  State<_PurchaseOrderSheet> createState() => _PurchaseOrderSheetState();
}

class _PurchaseOrderSheetState extends State<_PurchaseOrderSheet> {
  final _supplier = TextEditingController();
  final _productName = TextEditingController();
  final _quantity = TextEditingController();
  final _unitCost = TextEditingController();
  final _invoiceNumber = TextEditingController();
  final _notes = TextEditingController();
  String? _productId;
  bool _isCredit = false;
  bool _isSaving = false;
  PlatformFile? _invoiceAttachment;
  PlatformFile? _deliveryNoteAttachment;

  String get _businessId => widget.user.businessId ?? 'default_business';

  @override
  void dispose() {
    _supplier.dispose();
    _productName.dispose();
    _quantity.dispose();
    _unitCost.dispose();
    _invoiceNumber.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final quantity = double.tryParse(_quantity.text.trim());
    final unitCost = double.tryParse(_unitCost.text.trim());
    if (_supplier.text.trim().isEmpty ||
        _productName.text.trim().isEmpty ||
        quantity == null ||
        unitCost == null) {
      return;
    }
    BusinessPaymentSelection? payment;
    if (!_isCredit) {
      payment = await showBusinessPaymentDialog(
        context,
        businessId: _businessId,
        amount: quantity * unitCost,
        title: 'Pay supplier purchase',
      );
      if (payment == null || !mounted) return;
    }
    setState(() => _isSaving = true);
    try {
      final orderRef = FirebaseFirestore.instance
          .collection('purchase_orders')
          .doc();
      final invoiceUpload = await _uploadAttachment(
        orderRef.id,
        'invoice',
        _invoiceAttachment,
      );
      final deliveryUpload = await _uploadAttachment(
        orderRef.id,
        'delivery_note',
        _deliveryNoteAttachment,
      );
      final orderData = <String, dynamic>{
        'businessId': _businessId,
        'branchId': widget.user.branchId ?? 'main',
        'supplierName': _supplier.text.trim(),
        'productId': _productId,
        'productName': _productName.text.trim(),
        'quantity': quantity,
        'unitCost': unitCost,
        'totalAmount': quantity * unitCost,
        'invoiceNumber': _invoiceNumber.text.trim(),
        if (invoiceUpload != null) ...invoiceUpload,
        if (deliveryUpload != null) ...deliveryUpload,
        'invoiceStatus': 'unverified',
        'approvalStatus': 'pending',
        'receivingStatus': 'ordered',
        'paymentStatus': _isCredit ? 'unpaid' : 'paid',
        'isCredit': _isCredit,
        'notes': _notes.text.trim(),
        'createdBy': widget.user.id,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (_isCredit) {
        await orderRef.set(orderData);
      } else {
        await recordBusinessOutflow(
          sourceRef: orderRef,
          sourceData: orderData,
          businessId: _businessId,
          payment: payment!,
          amount: quantity * unitCost,
          sourceType: 'purchase',
          description: '${_supplier.text.trim()} - ${_productName.text.trim()}',
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save purchase: $e')));
    }
  }

  Future<void> _pickAttachment(bool invoice) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || !mounted) return;
    setState(() {
      if (invoice) {
        _invoiceAttachment = result.files.single;
      } else {
        _deliveryNoteAttachment = result.files.single;
      }
    });
  }

  Future<Map<String, dynamic>?> _uploadAttachment(
    String orderId,
    String type,
    PlatformFile? file,
  ) async {
    if (file == null || file.bytes == null) return null;
    final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final ref = FirebaseStorage.instance.ref(
      'purchase_documents/$orderId/${type}_$safeName',
    );
    await ref.putData(
      file.bytes!,
      SettableMetadata(contentType: _contentType(file.extension)),
    );
    final prefix = type == 'invoice'
        ? 'invoiceAttachment'
        : 'deliveryNoteAttachment';
    return {
      '${prefix}Url': await ref.getDownloadURL(),
      '${prefix}Name': file.name,
      '${prefix}StoragePath': ref.fullPath,
    };
  }

  String _contentType(String? extension) => switch (extension?.toLowerCase()) {
    'pdf' => 'application/pdf',
    'png' => 'image/png',
    _ => 'image/jpeg',
  };

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      title: 'Create Purchase Order',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(_supplier, 'Supplier name'),
          const SizedBox(height: 12),
          _productDropdown(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _field(
                  _quantity,
                  'Quantity',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(
                  _unitCost,
                  'Unit cost',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _field(_invoiceNumber, 'Invoice number', required: false),
          const SizedBox(height: 8),
          _attachmentButton(
            label: 'Invoice attachment (optional)',
            file: _invoiceAttachment,
            onPressed: () => _pickAttachment(true),
          ),
          const SizedBox(height: 8),
          _attachmentButton(
            label: 'Delivery note attachment (optional)',
            file: _deliveryNoteAttachment,
            onPressed: () => _pickAttachment(false),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Purchase on credit'),
            value: _isCredit,
            onChanged: (value) => setState(() => _isCredit = value),
          ),
          _field(_notes, 'Notes', required: false),
          const SizedBox(height: 16),
          _saveButton(_isSaving, _save, 'Save Purchase Order'),
        ],
      ),
    );
  }

  Widget _attachmentButton({
    required String label,
    required PlatformFile? file,
    required VoidCallback onPressed,
  }) => OutlinedButton.icon(
    onPressed: _isSaving ? null : onPressed,
    icon: const Icon(Icons.attach_file),
    label: Text(
      file == null ? label : file.name,
      overflow: TextOverflow.ellipsis,
    ),
  );

  Widget _productDropdown() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('products')
          .orderBy('name')
          .snapshots(),
      builder: (context, snapshot) {
        final docs =
            snapshot.data?.docs.where((doc) {
              return (doc.data()['businessId'] as String? ??
                      'default_business') ==
                  _businessId;
            }).toList() ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        return DropdownButtonFormField<String?>(
          initialValue: _productId,
          decoration: const InputDecoration(
            labelText: 'Product',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('Manual product')),
            ...docs.map((doc) {
              return DropdownMenuItem<String?>(
                value: doc.id,
                child: Text(doc.data()['name'] as String? ?? 'Product'),
              );
            }),
          ],
          onChanged: (value) {
            final selected = docs.where((doc) => doc.id == value).firstOrNull;
            setState(() {
              _productId = value;
              if (selected != null) {
                _productName.text =
                    selected.data()['name'] as String? ?? 'Product';
              }
            });
          },
        );
      },
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

class _BreakdownCard extends StatelessWidget {
  final String title;
  final List<_BreakdownRow> rows;
  final String emptyMessage;

  const _BreakdownCard({
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

class _PurchaseAnalytics {
  final double totalCost;
  final int pendingApproval;
  final double unpaidBalance;
  final double receivedQuantity;
  final Map<String, double> branchTotals;
  final Map<String, double> paymentTotals;

  const _PurchaseAnalytics({
    required this.totalCost,
    required this.pendingApproval,
    required this.unpaidBalance,
    required this.receivedQuantity,
    required this.branchTotals,
    required this.paymentTotals,
  });

  factory _PurchaseAnalytics.fromDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var total = 0.0;
    var pending = 0;
    var unpaid = 0.0;
    var received = 0.0;
    final branchTotals = <String, double>{};
    final paymentTotals = <String, double>{};

    for (final doc in docs) {
      final data = doc.data();
      final amount = (data['totalAmount'] as num?)?.toDouble() ?? 0;
      final quantity = (data['receivedQuantity'] as num?)?.toDouble() ?? 0;
      final approval = data['approvalStatus'] as String? ?? 'pending';
      final payment = data['paymentStatus'] as String? ?? 'unpaid';
      final branch = data['branchId'] as String? ?? 'main';
      total += amount;
      received += quantity;
      if (approval == 'pending') pending++;
      if (payment != 'paid') unpaid += amount;
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
    }

    return _PurchaseAnalytics(
      totalCost: total,
      pendingApproval: pending,
      unpaidBalance: unpaid,
      receivedQuantity: received,
      branchTotals: branchTotals,
      paymentTotals: paymentTotals,
    );
  }
}

DateTime _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

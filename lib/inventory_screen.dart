import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'models.dart';

class InventoryScreen extends StatefulWidget {
  final User user;
  final VoidCallback? onOpenMenu;
  const InventoryScreen({super.key, required this.user, this.onOpenMenu});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'sw_TZ',
    symbol: 'Tsh ',
    decimalDigits: 0,
  );

  String _money(num amount) => _currencyFormat.format(amount);
  String get _businessId => widget.user.businessId ?? 'default_business';

  Stream<QuerySnapshot<Map<String, dynamic>>> get _productsStream {
    return FirebaseFirestore.instance
        .collection('products')
        .orderBy('name')
        .snapshots();
  }

  Stream<Map<String, bool>> get _permissionsStream {
    final businessId = widget.user.businessId ?? 'default_business';
    final roleDocId = '${businessId}_${widget.user.role}';

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
    if (widget.user.role == UserRole.superAdmin) return true;
    if (permissions.isEmpty) return true;
    return permissions[featureId] == true;
  }

  void _openAddProductSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddProductSheet(user: widget.user),
    );
  }

  void _openPurchaseStockSheet(Product product) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _PurchaseStockSheet(product: product, user: widget.user),
    );
  }

  Product _productFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Product.fromMap({
      ...data,
      'id': (data['id'] as String?)?.isNotEmpty == true ? data['id'] : doc.id,
      'barcode': data['barcode'] ?? '',
      'category': data['category'] ?? 'General',
      'isSynced': 1,
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, bool>>(
      stream: _permissionsStream,
      builder: (context, permissionSnapshot) {
        final permissions = permissionSnapshot.data ?? {};
        final canAddProduct = _can(permissions, 'add_product');
        final canPurchaseStock = _can(permissions, 'purchase_stock');

        return Scaffold(
          appBar: AppBar(
            leading: widget.onOpenMenu == null
                ? null
                : IconButton(
                    tooltip: 'Menu',
                    onPressed: widget.onOpenMenu,
                    icon: const Icon(Icons.menu),
                  ),
            title: const Text('Inventory Management'),
            actions: [
              if (canAddProduct)
                IconButton(
                  tooltip: 'Add product',
                  icon: const Icon(Icons.add),
                  onPressed: _openAddProductSheet,
                ),
            ],
          ),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _productsStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text('Could not load products: ${snapshot.error}'),
                );
              }

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final productDocs = snapshot.data!.docs.where((doc) {
                final data = doc.data();
                return (data['businessId'] as String? ?? 'default_business') ==
                    _businessId;
              }).toList();
              final products = productDocs.map(_productFromDoc).toList();
              final lowStockCount = products
                  .where((product) => product.stockQuantity < 10)
                  .length;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: _InventorySummaryCard(
                            icon: Icons.warning,
                            color: Theme.of(context).colorScheme.error,
                            title: 'Low Stock',
                            value: '$lowStockCount items',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _InventorySummaryCard(
                            icon: Icons.inventory_2,
                            color: Theme.of(context).colorScheme.primary,
                            title: 'Products',
                            value: '${products.length} total',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: products.isEmpty
                        ? const Center(
                            child: Text(
                              'No Firebase products yet. Add one to start selling.',
                            ),
                          )
                        : ListView.separated(
                            itemCount: products.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final product = products[index];
                              final raw = productDocs[index].data();
                              final imageUrl = raw['imageUrl'] as String?;
                              final isLow = product.stockQuantity < 10;

                              return ListTile(
                                leading: _ProductAvatar(
                                  imageUrl: imageUrl,
                                  isLow: isLow,
                                ),
                                title: Text(
                                  product.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${product.category} | Barcode: ${product.barcode.isEmpty ? 'Not set' : product.barcode}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: SizedBox(
                                  width: 132,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              product.stockQuantity
                                                  .toStringAsFixed(0),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: isLow
                                                    ? Theme.of(
                                                        context,
                                                      ).colorScheme.error
                                                    : null,
                                              ),
                                            ),
                                            Text(
                                              _money(product.price),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (canPurchaseStock)
                                        IconButton(
                                          tooltip: 'Purchase stock',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () =>
                                              _openPurchaseStockSheet(product),
                                          icon: const Icon(
                                            Icons.add_shopping_cart,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                onTap: canPurchaseStock
                                    ? () => _openPurchaseStockSheet(product)
                                    : null,
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _InventorySummaryCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;

  const _InventorySummaryCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
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

class _ProductAvatar extends StatelessWidget {
  final String? imageUrl;
  final bool isLow;

  const _ProductAvatar({required this.imageUrl, required this.isLow});

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isLow
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CircleAvatar(backgroundImage: NetworkImage(imageUrl!));
    }

    return CircleAvatar(
      backgroundColor: backgroundColor,
      child: const Icon(Icons.inventory, color: Colors.white),
    );
  }
}

class _AddProductSheet extends StatefulWidget {
  final User user;

  const _AddProductSheet({required this.user});

  @override
  State<_AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends State<_AddProductSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  XFile? _image;
  String _selectedCategory = 'General';
  bool _isSaving = false;
  String get _businessId => widget.user.businessId ?? 'default_business';

  @override
  void dispose() {
    _nameController.dispose();
    _barcodeController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const _InventoryScannerPage()),
    );

    if (code == null || code.isEmpty || !mounted) return;
    setState(() => _barcodeController.text = code);
  }

  Future<void> _pickImage(ImageSource source) async {
    final image = await _imagePicker.pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 1200,
    );

    if (image == null || !mounted) return;
    setState(() => _image = image);
  }

  Future<String?> _uploadImage(String productId) async {
    if (_image == null) return null;

    final ref = FirebaseStorage.instance
        .ref()
        .child('product_images')
        .child('$productId.jpg');

    await ref.putFile(File(_image!.path));
    return ref.getDownloadURL();
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final barcode = _barcodeController.text.trim();
      final duplicate = await firestore
          .collection('products')
          .where('barcode', isEqualTo: barcode)
          .limit(1)
          .get();

      if (duplicate.docs.isNotEmpty) {
        throw Exception('A product with this barcode already exists.');
      }

      final productRef = firestore.collection('products').doc();
      final imageUrl = await _uploadImage(productRef.id);
      final product = Product(
        id: productRef.id,
        name: _nameController.text.trim(),
        barcode: barcode,
        price: double.parse(_priceController.text.trim()),
        stockQuantity: double.parse(_stockController.text.trim()),
        category: _selectedCategory,
        isSynced: 1,
      );

      await productRef.set({
        ...product.toMap(),
        'businessId': widget.user.businessId ?? 'default_business',
        'imageUrl': imageUrl,
        'createdBy': widget.user.id,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product added to Firebase.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save product: $e')));
    }
  }

  String? _requiredText(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    return null;
  }

  String? _requiredNumber(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final number = double.tryParse(value.trim());
    if (number == null || number < 0) return 'Enter a valid number';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Add Product',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Product name',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: _requiredText,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _barcodeController,
                  decoration: InputDecoration(
                    labelText: 'Barcode or QR code',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: 'Scan barcode or QR code',
                      onPressed: _isSaving ? null : _scanBarcode,
                      icon: const Icon(Icons.qr_code_scanner),
                    ),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: _requiredText,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _priceController,
                        decoration: const InputDecoration(
                          labelText: 'Price',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: _requiredNumber,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _stockController,
                        decoration: const InputDecoration(
                          labelText: 'Stock',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: _requiredNumber,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _categoryDropdown(),
                const SizedBox(height: 12),
                _imagePickerRow(),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _saveProduct,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_isSaving ? 'Saving...' : 'Save Product'),
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
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('product_categories')
          .orderBy('name')
          .snapshots(),
      builder: (context, snapshot) {
        final categories =
            snapshot.data?.docs
                .where(
                  (doc) =>
                      (doc.data()['businessId'] as String? ??
                          'default_business') ==
                      _businessId,
                )
                .map((doc) => doc.data()['name'] as String? ?? 'General')
                .where((name) => name.trim().isNotEmpty)
                .toSet()
                .toList() ??
            const <String>[];
        final values = [
          'General',
          ...categories.where((name) => name != 'General'),
        ];
        if (!values.contains(_selectedCategory)) {
          _selectedCategory = values.first;
        }

        return DropdownButtonFormField<String>(
          initialValue: _selectedCategory,
          decoration: const InputDecoration(
            labelText: 'Category',
            border: OutlineInputBorder(),
          ),
          items: values
              .map(
                (category) =>
                    DropdownMenuItem(value: category, child: Text(category)),
              )
              .toList(),
          onChanged: _isSaving
              ? null
              : (value) => setState(() => _selectedCategory = value!),
          validator: _requiredText,
        );
      },
    );
  }

  Widget _imagePickerRow() {
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
            image: _image == null
                ? null
                : DecorationImage(
                    image: FileImage(File(_image!.path)),
                    fit: BoxFit.cover,
                  ),
          ),
          child: _image == null ? const Icon(Icons.image_outlined) : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _isSaving
                    ? null
                    : () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.photo_camera),
                label: const Text('Camera'),
              ),
              OutlinedButton.icon(
                onPressed: _isSaving
                    ? null
                    : () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Gallery'),
              ),
              if (_image != null)
                IconButton(
                  tooltip: 'Remove image',
                  onPressed: _isSaving
                      ? null
                      : () => setState(() => _image = null),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PurchaseStockSheet extends StatefulWidget {
  final Product product;
  final User user;

  const _PurchaseStockSheet({required this.product, required this.user});

  @override
  State<_PurchaseStockSheet> createState() => _PurchaseStockSheetState();
}

class _PurchaseStockSheetState extends State<_PurchaseStockSheet> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _newPriceController = TextEditingController();
  bool _isSaving = false;
  bool _updateSellingPrice = false;

  @override
  void initState() {
    super.initState();
    _newPriceController.text = widget.product.price.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _newPriceController.dispose();
    super.dispose();
  }

  String? _requiredPositiveNumber(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final number = double.tryParse(value.trim());
    if (number == null || number <= 0) return 'Enter a number above 0';
    return null;
  }

  Future<void> _savePurchase() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final productRef = firestore
          .collection('products')
          .doc(widget.product.id);
      final purchaseRef = firestore.collection('stock_purchases').doc();
      final quantity = double.parse(_quantityController.text.trim());
      final newPrice = double.parse(_newPriceController.text.trim());

      await firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(productRef);
        if (!snapshot.exists) {
          throw Exception('Product no longer exists.');
        }

        final data = snapshot.data() ?? {};
        final currentStock = (data['stockQuantity'] as num?)?.toDouble() ?? 0;
        final currentPrice =
            (data['price'] as num?)?.toDouble() ?? widget.product.price;

        transaction.update(productRef, {
          'businessId': widget.user.businessId ?? 'default_business',
          'stockQuantity': currentStock + quantity,
          'price': _updateSellingPrice ? newPrice : currentPrice,
          'updatedAt': FieldValue.serverTimestamp(),
          'lastPurchasedAt': FieldValue.serverTimestamp(),
          'lastPurchasedQuantity': quantity,
          'lastPurchasedBy': widget.user.id,
        });

        transaction.set(purchaseRef, {
          'id': purchaseRef.id,
          'productId': widget.product.id,
          'productName': data['name'] ?? widget.product.name,
          'barcode': data['barcode'] ?? widget.product.barcode,
          'businessId': widget.user.businessId ?? 'default_business',
          'quantity': quantity,
          'previousStock': currentStock,
          'newStock': currentStock + quantity,
          'previousPrice': currentPrice,
          'newPrice': _updateSellingPrice ? newPrice : currentPrice,
          'purchasedBy': widget.user.id,
          'branchId': widget.user.branchId ?? 'main',
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${widget.product.name} stock increased by ${quantity.toStringAsFixed(0)}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not purchase stock: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Purchase Stock',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Icon(Icons.inventory_2)),
                  title: Text(widget.product.name),
                  subtitle: Text(
                    'Current stock: ${widget.product.stockQuantity.toStringAsFixed(0)}',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _quantityController,
                  decoration: const InputDecoration(
                    labelText: 'Quantity purchased',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _requiredPositiveNumber,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Update selling price'),
                  value: _updateSellingPrice,
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _updateSellingPrice = value),
                ),
                if (_updateSellingPrice) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _newPriceController,
                    decoration: const InputDecoration(
                      labelText: 'New selling price',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: _requiredPositiveNumber,
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _savePurchase,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_shopping_cart),
                    label: Text(_isSaving ? 'Saving...' : 'Add Stock'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InventoryScannerPage extends StatefulWidget {
  const _InventoryScannerPage();

  @override
  State<_InventoryScannerPage> createState() => _InventoryScannerPageState();
}

class _InventoryScannerPageState extends State<_InventoryScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue?.trim();
      if (code == null || code.isEmpty) continue;

      _hasScanned = true;
      Navigator.pop(context, code);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Product Code'),
        actions: [
          IconButton(
            tooltip: 'Toggle torch',
            onPressed: _controller.toggleTorch,
            icon: const Icon(Icons.flash_on),
          ),
          IconButton(
            tooltip: 'Switch camera',
            onPressed: _controller.switchCamera,
            icon: const Icon(Icons.cameraswitch),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 260,
              height: 180,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.black.withValues(alpha: 0.65),
              child: const SafeArea(
                top: false,
                child: Text(
                  'Scan the product barcode or QR code to fill the product code field.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'app_loading_indicator.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'commerce_rules.dart';
import 'database_helper.dart';
import 'models.dart';
import 'notification_inbox_page.dart';
import 'product_recognition_camera.dart';

class POSScreen extends StatefulWidget {
  final User user;
  final VoidCallback? onOpenMenu;
  final Map<String, bool>? permissions;
  const POSScreen({
    super.key,
    required this.user,
    this.onOpenMenu,
    this.permissions,
  });

  @override
  State<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends State<POSScreen> {
  final List<CartItem> _cart = [];
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _paidController = TextEditingController();
  final TextEditingController _checkoutCustomerController =
      TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final SpeechToText _speech = SpeechToText();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'sw_TZ',
    symbol: 'Tsh ',
    decimalDigits: 0,
  );

  List<Product> _products = [];
  List<_PosCustomer> _customers = [];
  CommerceRules _rules = const CommerceRules(priceGroups: [], taxRules: []);
  final List<List<CartItem>> _suspendedCarts = [];
  String? _loadError;
  String _paymentMethod = 'Cash';
  double _openingCash = 0;
  double _cashSalesTotal = 0;
  bool _cashRegisterOpened = false;
  bool _sellOnCredit = false;
  bool _isLoading = true;
  bool _isCheckingOut = false;
  bool _speechInitialized = false;
  _VoiceSearchTarget? _listeningTarget;
  String _speechLanguage = 'en';
  bool _productQueryFromVoice = false;
  bool _customerQueryFromVoice = false;
  String get _businessId => widget.user.businessId ?? 'default_business';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_refreshIfMounted);
    _paidController.addListener(_refreshIfMounted);
    _checkoutCustomerController.addListener(_refreshIfMounted);
    _loadProducts();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.removeListener(_refreshIfMounted);
    _paidController.removeListener(_refreshIfMounted);
    _checkoutCustomerController.removeListener(_refreshIfMounted);
    _searchController.dispose();
    _paidController.dispose();
    _checkoutCustomerController.dispose();
    _searchFocusNode.dispose();
    _speech.cancel();
    super.dispose();
  }

  void _refreshIfMounted() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('products')
          .orderBy('name')
          .get();
      final rules = await _loadCommerceRules();
      final products = <Product>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if ((data['businessId'] as String? ?? 'default_business') !=
            _businessId) {
          continue;
        }

        final product = _tryProductFromDoc(doc);
        if (product != null) products.add(product);
      }

      await Future.wait(
        products.map(
          (product) => DatabaseHelper.instance.insertProduct(product),
        ),
      );

      if (!mounted) return;

      setState(() {
        _products = products;
        _rules = rules;
        _cart.removeWhere(
          (item) => !_products.any((product) => product.id == item.product.id),
        );
        if (_paymentMethod == 'Cash' &&
            !_sellOnCredit &&
            _cart.isNotEmpty &&
            _paidController.text.trim().isEmpty) {
          _paidController.text = _payableAmount.toStringAsFixed(0);
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _products = [];
        _loadError = 'Could not load products from Firebase.';
        _isLoading = false;
      });
      _showMessage('Could not load products from Firebase: $e');
    }
  }

  Future<void> _loadCustomers() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('customers')
          .get();
      final customers =
          snapshot.docs
              .where((doc) {
                return (doc.data()['businessId'] as String? ??
                        'default_business') ==
                    _businessId;
              })
              .map(_PosCustomer.fromDoc)
              .toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
      if (mounted) setState(() => _customers = customers);
    } catch (e) {
      debugPrint('Could not load POS customers: $e');
    }
  }

  Future<CommerceRules> _loadCommerceRules() async {
    try {
      return await CommerceRules.load(_businessId);
    } catch (e) {
      debugPrint('Could not load commerce rules: $e');
      return const CommerceRules(priceGroups: [], taxRules: []);
    }
  }

  Product _productFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Product.fromMap({
      ...data,
      'id': (data['id'] as String?)?.isNotEmpty == true ? data['id'] : doc.id,
      'isSynced': 1,
    });
  }

  Product? _tryProductFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      return _productFromDoc(doc);
    } catch (e) {
      debugPrint('Skipped invalid product ${doc.id}: $e');
      return null;
    }
  }

  List<Product> get _filteredProducts {
    final query = _normalizeSearch(_searchController.text);
    if (query.isEmpty) return _products;

    return _products.where((product) {
      return _matchesSearch(query, [
        product.name,
        product.barcode,
        product.category,
        product.brandName ?? '',
        ...product.aliases,
      ]);
    }).toList();
  }

  List<_PosCustomer> get _filteredCustomers {
    final query = _normalizeSearch(_checkoutCustomerController.text);
    if (query.isEmpty) return const [];
    return _customers
        .where((customer) {
          return _matchesSearch(query, [
            customer.name,
            customer.phone,
            ...customer.aliases,
          ]);
        })
        .take(5)
        .toList();
  }

  String _normalizeSearch(String value) {
    var normalized = value.toLowerCase().trim();
    for (final phrase in const [
      'search for ',
      'search ',
      'find ',
      'tafuta ',
      'nitafutie ',
    ]) {
      if (normalized.startsWith(phrase)) {
        normalized = normalized.substring(phrase.length);
        break;
      }
    }
    return normalized
        .replaceAll(RegExp(r'[^a-z0-9\u00c0-\u024f]+'), ' ')
        .trim();
  }

  bool _matchesSearch(String query, Iterable<String> values) {
    final compactQuery = query.replaceAll(' ', '');
    return values.any((value) {
      final normalized = _normalizeSearch(value);
      return normalized.contains(query) ||
          normalized.replaceAll(' ', '').contains(compactQuery);
    });
  }

  Future<void> _toggleVoiceSearch(_VoiceSearchTarget target) async {
    if (_listeningTarget != null) {
      await _speech.stop();
      if (mounted) setState(() => _listeningTarget = null);
      return;
    }

    if (!_speechInitialized) {
      final available = await _speech.initialize(
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') && mounted) {
            setState(() => _listeningTarget = null);
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() => _listeningTarget = null);
          _showMessage('Voice search error: ${error.errorMsg}');
        },
      );
      if (!available) {
        _showMessage(
          'Speech recognition is unavailable. Check microphone permission and installed speech languages.',
        );
        return;
      }
      _speechInitialized = true;
    }

    final locales = await _speech.locales();
    final desiredPrefix = _speechLanguage == 'sw' ? 'sw' : 'en';
    String? localeId;
    for (final locale in locales) {
      if (locale.localeId.toLowerCase().startsWith(desiredPrefix)) {
        localeId = locale.localeId;
        break;
      }
    }
    if (localeId == null) {
      _showMessage(
        _speechLanguage == 'sw'
            ? 'Kiswahili speech recognition is not installed on this device.'
            : 'English speech recognition is not installed on this device.',
      );
      return;
    }

    setState(() => _listeningTarget = target);
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.search,
      ),
      onResult: (result) {
        if (!mounted || result.recognizedWords.trim().isEmpty) return;
        final controller = target == _VoiceSearchTarget.product
            ? _searchController
            : _checkoutCustomerController;
        controller.value = TextEditingValue(
          text: result.recognizedWords,
          selection: TextSelection.collapsed(
            offset: result.recognizedWords.length,
          ),
        );
        setState(() {
          if (target == _VoiceSearchTarget.product) {
            _productQueryFromVoice = true;
          } else {
            _customerQueryFromVoice = true;
          }
        });
      },
    );
  }

  Future<bool> _confirmVoiceChange(String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm voice selection'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;
  }

  double get _subtotalAmount =>
      _cart.fold(0, (total, item) => total + item.subtotal);
  double get _discountAmount =>
      _cart.fold(0, (total, item) => total + item.discountAmount);
  double get _taxAmount =>
      _cart.fold(0, (total, item) => total + item.taxAmount);
  double get _totalAmount => _cart.fold(0, (total, item) => total + item.total);
  double get _payableAmount => _totalAmount.clamp(0, double.infinity);
  double get _cashReceived => _amountFromInput(_paidController.text);
  double get _changeAmount {
    if (_sellOnCredit || _paymentMethod != 'Cash') return 0;
    if (_cashReceived <= _payableAmount) return 0;
    return _cashReceived - _payableAmount;
  }

  double get _netCashKept {
    if (_sellOnCredit || _paymentMethod != 'Cash') return 0;
    if (_cashReceived <= 0) return 0;
    return (_cashReceived - _changeAmount).clamp(0, _payableAmount);
  }

  String? get _checkoutCustomerName {
    final value = _checkoutCustomerController.text.trim();
    return value.isEmpty ? null : value;
  }

  int _quantityInCart(Product product) {
    final index = _cart.indexWhere((item) => item.product.id == product.id);
    if (index == -1) return 0;
    return _cart[index].quantity;
  }

  String _money(num amount) => _currencyFormat.format(amount);

  double _amountFromInput(String value) {
    final normalized = value.replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (normalized.isEmpty || normalized == '-' || normalized == '.') return 0;
    return double.tryParse(normalized) ?? 0;
  }

  void _addToCart(Product product) {
    if (_quantityInCart(product) >= product.stockQuantity) {
      _showMessage('${product.name} has no more stock available.');
      return;
    }

    setState(() {
      final index = _cart.indexWhere((item) => item.product.id == product.id);
      if (index != -1) {
        _cart[index].quantity++;
        _repriceCartItem(_cart[index]);
      } else {
        final priced = _rules.price(product);
        _cart.add(
          CartItem(
            product: product,
            unitPrice: priced.unitPrice,
            discountAmount: priced.discountPerUnit,
            taxAmount: priced.taxPerUnit,
            pricingNote: priced.note,
          ),
        );
      }
      if (!_sellOnCredit &&
          _paymentMethod == 'Cash' &&
          _paidController.text.trim().isEmpty) {
        _paidController.text = _payableAmount.toStringAsFixed(0);
      }
    });
  }

  void _repriceCartItem(CartItem item) {
    final priced = _rules.price(item.product);
    item.unitPrice = priced.unitPrice;
    item.discountAmount = priced.discountPerUnit * item.quantity;
    item.taxAmount = priced.taxPerUnit * item.quantity;
    item.pricingNote = priced.note;
  }

  void _submitSearch(String value) {
    // Search results are selected manually to prevent accidental additions.
  }

  Product? _findProductByCodeOrName(String value) {
    final query = value.trim().toLowerCase();
    if (query.isEmpty) return null;

    for (final product in _products) {
      if (product.barcode.toLowerCase() == query ||
          product.name.toLowerCase() == query) {
        return product;
      }
    }

    return null;
  }

  void _handleScannedCode(String code) {
    final product = _findProductByCodeOrName(code);
    if (product == null) {
      _showMessage('No product found for barcode $code.');
      return;
    }

    _addToCart(product);
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.alert);
  }

  Future<void> _openScanner() async {
    if (_products.isEmpty) {
      _showMessage('Load Firebase products before scanning.');
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            _BarcodeScannerPage(onCodeDetected: _handleScannedCode),
      ),
    );
    _searchFocusNode.requestFocus();
  }

  Future<void> _openAiProductCamera() async {
    if (_products.isEmpty) {
      _showMessage('Load Firebase products before using AI recognition.');
      return;
    }
    final query = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ProductRecognitionCamera(
          productNames: _products.map((product) => product.name).toList(),
        ),
      ),
    );
    if (query == null || query.trim().isEmpty || !mounted) return;
    setState(() {
      _searchController.text = query.trim();
      _productQueryFromVoice = false;
    });
    _searchFocusNode.requestFocus();
    _showMessage(
      'AI recognized "$query". Select the correct product from the results.',
    );
  }

  void _removeOne(CartItem item) {
    setState(() {
      if (item.quantity > 1) {
        item.quantity--;
        _repriceCartItem(item);
      } else {
        _cart.remove(item);
      }
    });
  }

  void _removeItem(CartItem item) {
    setState(() => _cart.remove(item));
  }

  Future<void> _checkout() async {
    final payment = _paymentFromCheckoutPanel();
    if (payment == null) {
      _showMessage(
        _sellOnCredit
            ? 'Enter the customer name for credit sale.'
            : 'Enter enough cash before completing this sale.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Sale'),
        content: Text(
          'Complete this ${payment.isCredit ? 'credit ' : ''}sale for ${_money(_totalAmount)}?',
        ),
        actions: [
          NotificationBellButton(user: widget.user),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.check),
            label: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isCheckingOut = true);

    try {
      final now = DateTime.now();
      final receiptItems = _cart
          .map(
            (item) => CartItem(
              product: item.product,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              discountAmount: item.discountAmount,
              taxAmount: item.taxAmount,
              pricingNote: item.pricingNote,
            ),
          )
          .toList();
      final sale = Sale(
        id: 'sale_${now.microsecondsSinceEpoch}',
        itemsJson: jsonEncode(
          _cart.map((item) {
            return {
              'productId': item.product.id,
              'name': item.product.name,
              'barcode': item.product.barcode,
              'basePrice': item.product.price,
              'price': item.unitPrice,
              'quantity': item.quantity,
              'discount': item.discountAmount,
              'tax': item.taxAmount,
              'total': item.total,
              'pricingNote': item.pricingNote,
            };
          }).toList(),
        ),
        totalAmount: _totalAmount,
        timestamp: now.toIso8601String(),
        branchId: widget.user.branchId ?? 'main',
        cashierId: widget.user.id,
        paymentMethod: payment.isCredit ? 'Credit' : _paymentMethod,
        paidAmount: payment.paidAmount,
        changeAmount: payment.changeAmount,
        discountAmount: _discountAmount,
        taxAmount: _taxAmount,
        isCredit: payment.isCredit,
        customerName: payment.customerName,
      );

      await _recordCashMovement(sale);
      await DatabaseHelper.instance.insertSale(sale);
      for (final item in receiptItems) {
        await DatabaseHelper.instance.updateProductStock(
          item.product.id,
          item.product.stockQuantity - item.quantity,
        );
      }

      if (!mounted) return;
      final receiptGenerated = await _printReceipt(sale, receiptItems);
      var syncedToFirebase = false;
      try {
        await _saveSaleToFirebase(sale, receiptItems);
        await DatabaseHelper.instance.updateSaleSyncStatus(sale.id, 1);
        syncedToFirebase = true;
      } catch (e) {
        debugPrint('Sale saved locally but Firebase sync failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _paidController.clear();
        _checkoutCustomerController.clear();
        _sellOnCredit = false;
        _paymentMethod = 'Cash';
        _isCheckingOut = false;
      });
      await _loadProducts();
      _showMessage(
        [
          'Sale completed',
          if (receiptGenerated) 'receipt generated',
          syncedToFirebase ? 'synced' : 'saved locally',
        ].join(', '),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCheckingOut = false);
      _showMessage('Could not complete sale: $e');
    }
  }

  _PaymentResult? _paymentFromCheckoutPanel() {
    if (_sellOnCredit || _paymentMethod == 'Credit') {
      final customerName = _checkoutCustomerName;
      if (customerName == null) return null;
      return _PaymentResult(
        paidAmount: 0,
        changeAmount: 0,
        isCredit: true,
        customerName: customerName,
      );
    }

    if (_paymentMethod == 'Cash') {
      if (_cashReceived < _payableAmount) return null;
      return _PaymentResult(
        paidAmount: _cashReceived,
        changeAmount: _changeAmount,
        isCredit: false,
        customerName: _checkoutCustomerName,
      );
    }

    return _PaymentResult(
      paidAmount: _payableAmount,
      changeAmount: 0,
      isCredit: false,
      customerName: _checkoutCustomerName,
    );
  }

  Future<bool> _printReceipt(Sale sale, List<CartItem> items) async {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Center(
            child: pw.Text(
              'POS APP',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Receipt: ${sale.id}'),
          pw.Text('Date: ${dateFormat.format(DateTime.parse(sale.timestamp))}'),
          pw.Text('Cashier: ${widget.user.name}'),
          pw.Text('Payment: ${sale.paymentMethod}'),
          if (sale.customerName?.isNotEmpty == true)
            pw.Text('Customer: ${sale.customerName}'),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const ['Item', 'Qty', 'Price', 'Total'],
            data: items.map((item) {
              return [
                item.product.name,
                item.quantity.toStringAsFixed(0),
                _money(item.unitPrice),
                _money(item.total),
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Discount: ${_money(sale.discountAmount)}'),
          ),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Tax: ${_money(sale.taxAmount)}'),
          ),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'TOTAL: ${_money(sale.totalAmount)}',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Center(child: pw.Text('Thank you!')),
        ],
      ),
    );

    try {
      await Printing.layoutPdf(
        name: 'receipt_${sale.id}.pdf',
        onLayout: (_) async => doc.save(),
      );
      return true;
    } on MissingPluginException {
      if (!mounted) return false;
      _showMessage(
        'Printing plugin is not registered. Stop the app completely and rebuild it.',
      );
      return false;
    }
  }

  Future<void> _openCashRegister() async {
    if (_cashRegisterOpened) {
      await _showCashRegisterSummary();
      return;
    }

    final controller = TextEditingController(
      text: _openingCash == 0 ? '' : _openingCash.toStringAsFixed(0),
    );
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open Cash Register'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Opening cash',
            border: OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              double.tryParse(controller.text.trim()) ?? 0,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (amount == null) return;

    if (!mounted) return;
    setState(() {
      _openingCash = amount;
      _cashSalesTotal = 0;
      _cashRegisterOpened = true;
    });
    _showMessage('Cash register opened with ${_money(amount)}.');
  }

  Future<void> _showCashRegisterSummary() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cash Register'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PaymentSummaryLine('Opening cash', _money(_openingCash)),
            _PaymentSummaryLine('Net cash sales', _money(_cashSalesTotal)),
            _PaymentSummaryLine(
              'Expected cash',
              _money(_openingCash + _cashSalesTotal),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _closeCashRegister();
            },
            icon: const Icon(Icons.lock),
            label: const Text('Close Register'),
          ),
        ],
      ),
    );
  }

  Future<void> _closeCashRegister() async {
    setState(() {
      _openingCash = 0;
      _cashSalesTotal = 0;
      _cashRegisterOpened = false;
    });
    _showMessage('Cash register closed.');
  }

  Future<void> _recordCashMovement(Sale sale) async {
    if (sale.isCredit || sale.paymentMethod != 'Cash') return;
    if (!_cashRegisterOpened) return;

    final cashKept = _cashKeptForSale(sale);
    if (!mounted) return;
    setState(() => _cashSalesTotal += cashKept);
  }

  double _cashKeptForSale(Sale sale) {
    if (sale.isCredit || sale.paymentMethod != 'Cash') return 0;
    return (sale.paidAmount - sale.changeAmount).clamp(0, double.infinity);
  }

  void _suspendCart() {
    if (_cart.isEmpty) return;
    setState(() {
      _suspendedCarts.add(
        _cart
            .map(
              (item) => CartItem(
                product: item.product,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                discountAmount: item.discountAmount,
                taxAmount: item.taxAmount,
                pricingNote: item.pricingNote,
              ),
            )
            .toList(),
      );
      _cart.clear();
    });
    _showMessage('Sale suspended.');
  }

  void _resumeSuspendedCart(int index) {
    setState(() {
      _cart
        ..clear()
        ..addAll(_suspendedCarts.removeAt(index));
    });
  }

  void _showSuspendedSales() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: _suspendedCarts.isEmpty
            ? const SizedBox(
                height: 120,
                child: Center(child: Text('No suspended sales.')),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: _suspendedCarts.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final items = _suspendedCarts[index];
                  final total = items.fold<double>(
                    0,
                    (runningTotal, item) => runningTotal + item.total,
                  );
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.pause)),
                    title: Text('${items.length} item types'),
                    subtitle: Text(_money(total)),
                    onTap: () {
                      Navigator.pop(context);
                      _resumeSuspendedCart(index);
                    },
                  );
                },
              ),
      ),
    );
  }

  Future<void> _saveSaleToFirebase(Sale sale, List<CartItem> items) async {
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    final saleRef = firestore.collection('sales').doc(sale.id);

    for (final item in items) {
      batch.update(firestore.collection('products').doc(item.product.id), {
        'stockQuantity': FieldValue.increment(-item.quantity),
      });
    }

    batch.set(saleRef, {
      ...sale.toMap(),
      'businessId': _businessId,
      'isSynced': 1,
    });

    await batch.commit();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      appBar: AppBar(
        leading: widget.onOpenMenu == null
            ? null
            : IconButton(
                tooltip: 'Menu',
                onPressed: widget.onOpenMenu,
                icon: const Icon(Icons.menu),
              ),
        title: const Text('Point of Sale'),
        actions: [
          IconButton(
            tooltip: _cashRegisterOpened
                ? 'Cash register opened'
                : 'Open cash register',
            onPressed: _openCashRegister,
            icon: Icon(
              _cashRegisterOpened
                  ? Icons.account_balance_wallet
                  : Icons.point_of_sale,
            ),
          ),
          IconButton(
            tooltip: 'Suspended sales',
            onPressed: _showSuspendedSales,
            icon: Badge(
              isLabelVisible: _suspendedCarts.isNotEmpty,
              label: Text('${_suspendedCarts.length}'),
              child: const Icon(Icons.pause_circle_outline),
            ),
          ),
          IconButton(
            tooltip: 'Scan barcode or QR code',
            onPressed: _isLoading ? null : _openScanner,
            icon: const Icon(Icons.qr_code_scanner),
          ),
          if (widget.user.role == UserRole.superAdmin ||
              widget.permissions == null ||
              widget.permissions!['ai_product_recognition'] == true)
            IconButton(
              tooltip: 'Recognize product with AI camera',
              onPressed: _isLoading ? null : _openAiProductCamera,
              icon: const Icon(Icons.center_focus_strong),
            ),
          IconButton(
            tooltip: 'Refresh products',
            onPressed: _isLoading ? null : _loadProducts,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: ModernLoadingIndicator())
          : Column(
              children: [
                _searchPane(keyboardVisible: keyboardVisible),
                const Divider(height: 1),
                Expanded(
                  child: _scrollableCheckoutArea(
                    keyboardVisible: keyboardVisible,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _scrollableCheckoutArea({required bool keyboardVisible}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              children: [
                _cartHeader(compact: keyboardVisible),
                _cartList(),
                if (keyboardVisible) _compactCartTotal() else _checkoutPanel(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _searchPane({required bool keyboardVisible}) {
    final products = _filteredProducts;
    final query = _searchController.text.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.translate, size: 18),
              const SizedBox(width: 8),
              Text(
                'Voice language:',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _speechLanguage,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'sw', child: Text('Kiswahili')),
                ],
                onChanged: _listeningTarget == null
                    ? (value) {
                        if (value != null) {
                          setState(() => _speechLanguage = value);
                        }
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SearchBar(
            controller: _searchController,
            focusNode: _searchFocusNode,
            hintText: 'Search product name or barcode',
            leading: const Icon(Icons.search),
            trailing: [
              IconButton(
                tooltip: _listeningTarget == _VoiceSearchTarget.product
                    ? 'Stop listening'
                    : 'Search products by voice',
                onPressed: () => _toggleVoiceSearch(_VoiceSearchTarget.product),
                icon: Icon(
                  _listeningTarget == _VoiceSearchTarget.product
                      ? Icons.mic
                      : Icons.mic_none,
                  color: _listeningTarget == _VoiceSearchTarget.product
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
              if (_searchController.text.isNotEmpty)
                IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    _productQueryFromVoice = false;
                    _searchFocusNode.requestFocus();
                  },
                  icon: const Icon(Icons.close),
                ),
            ],
            textInputAction: TextInputAction.search,
            onChanged: (_) => _productQueryFromVoice = false,
            onSubmitted: _submitSearch,
          ),
          const SizedBox(height: 8),
          Text(
            query.isEmpty
                ? 'Search products or use the scanner in the app bar.'
                : '${products.length} result${products.length == 1 ? '' : 's'} for "$query"',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (_loadError != null) ...[
            const SizedBox(height: 8),
            Text(
              _loadError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (query.isNotEmpty) ...[
            const SizedBox(height: 8),
            _searchResults(products, maxHeight: keyboardVisible ? 120 : 220),
          ],
        ],
      ),
    );
  }

  Widget _searchResults(List<Product> products, {required double maxHeight}) {
    if (products.isEmpty) {
      return SizedBox(
        height: 56,
        child: Center(child: Text(_loadError ?? 'No product found.')),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: products.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final product = products[index];
          final quantityInCart = _quantityInCart(product);
          final remaining = product.stockQuantity - quantityInCart;
          final outOfStock = remaining <= 0;

          return ListTile(
            dense: true,
            leading: Icon(outOfStock ? Icons.block : Icons.inventory_2),
            title: Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${product.barcode} | ${product.category} | ${remaining.toStringAsFixed(0)} left',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(_money(product.price)),
            enabled: !outOfStock,
            onTap: outOfStock
                ? null
                : () async {
                    if (_productQueryFromVoice) {
                      final confirmed = await _confirmVoiceChange(
                        'Add ${product.name} to the cart?',
                      );
                      if (!confirmed) return;
                    }
                    _addToCart(product);
                    _searchFocusNode.requestFocus();
                  },
          );
        },
      ),
    );
  }

  Widget _cartHeader({required bool compact}) {
    if (compact) {
      return SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Icon(Icons.shopping_cart, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cart - ${_cart.length} item types',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Clear cart',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                onPressed: _cart.isEmpty ? null : () => setState(_cart.clear),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      );
    }

    return ListTile(
      leading: const Icon(Icons.shopping_cart),
      title: const Text('Cart', style: TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text('${_cart.length} item types'),
      trailing: TextButton.icon(
        onPressed: _cart.isEmpty ? null : () => setState(_cart.clear),
        icon: const Icon(Icons.delete_outline),
        label: const Text('Clear'),
      ),
    );
  }

  Widget _cartList() {
    if (_cart.isEmpty) {
      return const SizedBox(
        height: 96,
        child: Center(child: Text('Tap products to add them.')),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: _cart.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = _cart[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.quantity} x ${_money(item.product.price)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Remove one',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                onPressed: () => _removeOne(item),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 54, maxWidth: 86),
                child: Text(
                  _money(item.total),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Remove item',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                onPressed: () => _removeItem(item),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _compactCartTotal() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          Text(
            _money(_totalAmount),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _checkoutPanel() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 380;

        return Container(
          padding: EdgeInsets.fromLTRB(12, compact ? 8 : 12, 12, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: SafeArea(
            top: false,
            minimum: EdgeInsets.zero,
            child: compact
                ? _compactCheckoutContent()
                : _regularCheckoutContent(),
          ),
        );
      },
    );
  }

  Widget _regularCheckoutContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _cashRegisterBanner(),
        _amountBreakdown(),
        const SizedBox(height: 10),
        _saleTypeSelector(),
        const SizedBox(height: 10),
        _paymentDetailsFields(),
        const SizedBox(height: 10),
        _totalRow(fontSize: 18),
        const SizedBox(height: 6),
        _paymentPreviewRows(),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _suspendButton(height: 48)),
            const SizedBox(width: 10),
            Expanded(child: _payButton(height: 48)),
          ],
        ),
      ],
    );
  }

  Widget _compactCheckoutContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _saleTypeSelector(),
        const SizedBox(height: 8),
        _paymentDetailsFields(isDense: true),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _totalRow(fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(child: _payButton(height: 44, showIcon: false)),
          ],
        ),
        const SizedBox(height: 6),
        _paymentPreviewRows(),
      ],
    );
  }

  Widget _cashRegisterBanner() {
    return Row(
      children: [
        Icon(
          _cashRegisterOpened ? Icons.lock_open : Icons.info_outline,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _cashRegisterOpened
                ? 'Register: ${_money(_openingCash + _cashSalesTotal)} expected'
                : 'Cash register is optional. Open it before selling if needed.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _saleTypeSelector() {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(
          value: false,
          label: Text('Cash sale'),
          icon: Icon(Icons.payments),
        ),
        ButtonSegment(
          value: true,
          label: Text('Credit sale'),
          icon: Icon(Icons.schedule),
        ),
      ],
      selected: {_sellOnCredit},
      onSelectionChanged: (selection) {
        setState(() {
          _sellOnCredit = selection.first;
          if (_sellOnCredit) {
            _paymentMethod = 'Credit';
          } else if (_paymentMethod == 'Credit') {
            _paymentMethod = 'Cash';
          }
        });
      },
    );
  }

  Widget _amountBreakdown() {
    return Column(
      children: [
        _miniTotalRow('Subtotal', _subtotalAmount),
        _miniTotalRow('Discount', -_discountAmount),
        _miniTotalRow('Tax', _taxAmount),
      ],
    );
  }

  Widget _paymentDetailsFields({bool isDense = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _customerField(isDense: isDense),
        const SizedBox(height: 10),
        if (_sellOnCredit)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Credit sale will record the balance under this customer.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else ...[
          _paymentMethodField(isDense: isDense),
          if (_paymentMethod == 'Cash') ...[
            const SizedBox(height: 10),
            _cashReceivedField(isDense: isDense),
          ],
        ],
      ],
    );
  }

  Widget _customerField({bool isDense = false}) {
    final matches = _filteredCustomers;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _checkoutCustomerController,
          onChanged: (_) => _customerQueryFromVoice = false,
          decoration: InputDecoration(
            labelText: _sellOnCredit
                ? 'Search customer'
                : 'Search customer (optional)',
            hintText: 'Name, phone, or alias',
            border: const OutlineInputBorder(),
            contentPadding: isDense
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
                : null,
            suffixIcon: IconButton(
              tooltip: _listeningTarget == _VoiceSearchTarget.customer
                  ? 'Stop listening'
                  : 'Search customers by voice',
              onPressed: () => _toggleVoiceSearch(_VoiceSearchTarget.customer),
              icon: Icon(
                _listeningTarget == _VoiceSearchTarget.customer
                    ? Icons.mic
                    : Icons.mic_none,
                color: _listeningTarget == _VoiceSearchTarget.customer
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
            ),
          ),
          textInputAction: TextInputAction.next,
        ),
        if (matches.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 144),
            child: Card(
              margin: const EdgeInsets.only(top: 4),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: matches.length,
                itemBuilder: (context, index) {
                  final customer = matches[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_outline),
                    title: Text(customer.name),
                    subtitle: customer.phone.isEmpty
                        ? null
                        : Text(customer.phone),
                    onTap: () async {
                      if (_customerQueryFromVoice) {
                        final confirmed = await _confirmVoiceChange(
                          'Use ${customer.name} for this sale?',
                        );
                        if (!confirmed) return;
                      }
                      setState(() {
                        _checkoutCustomerController.text = customer.name;
                        _checkoutCustomerController.selection =
                            TextSelection.collapsed(
                              offset: customer.name.length,
                            );
                        _customerQueryFromVoice = false;
                      });
                    },
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _paymentPreviewRows() {
    final paid = _sellOnCredit
        ? 0.0
        : _paymentMethod == 'Cash'
        ? _cashReceived
        : _payableAmount;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _miniTotalRow('Paid', paid),
        _miniTotalRow('Change', _changeAmount),
        if (!_sellOnCredit && _paymentMethod == 'Cash')
          _miniTotalRow('Net cash kept', _netCashKept),
        if (_sellOnCredit && _checkoutCustomerName == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Customer name is required for credit sale.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ),
        if (!_sellOnCredit &&
            _paymentMethod == 'Cash' &&
            _cart.isNotEmpty &&
            _cashReceived < _payableAmount)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Enter cash received above the total to calculate change.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _miniTotalRow(String label, double amount) {
    return Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const Spacer(),
        Text(_money(amount), style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _paymentMethodField({
    bool isDense = false,
    ValueChanged<String>? onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: _sellOnCredit ? 'Credit' : _paymentMethod,
      isDense: isDense,
      decoration: InputDecoration(
        labelText: 'Payment Method',
        border: const OutlineInputBorder(),
        contentPadding: isDense
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
            : null,
      ),
      items: const [
        DropdownMenuItem(value: 'Cash', child: Text('Cash')),
        DropdownMenuItem(value: 'Card', child: Text('Card')),
        DropdownMenuItem(value: 'Mobile Money', child: Text('Mobile Money')),
        DropdownMenuItem(value: 'Credit', child: Text('Credit')),
      ],
      onChanged: (value) {
        if (value == null) return;
        if (!mounted) return;
        setState(() {
          _paymentMethod = value;
          _sellOnCredit = value == 'Credit';
        });
        onChanged?.call(value);
      },
    );
  }

  Widget _cashReceivedField({bool isDense = false}) {
    return TextField(
      controller: _paidController,
      decoration: InputDecoration(
        labelText: 'Cash customer paid',
        helperText:
            'Total: ${_money(_payableAmount)} | Change returned: ${_money(_changeAmount)}',
        border: const OutlineInputBorder(),
        contentPadding: isDense
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
            : null,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => _refreshIfMounted(),
    );
  }

  Widget _totalRow({required double fontSize}) {
    return Row(
      children: [
        Text(
          'Total',
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            _money(_totalAmount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _payButton({required double height, bool showIcon = true}) {
    final paymentCanComplete =
        (_sellOnCredit && _checkoutCustomerName != null) ||
        (!_sellOnCredit &&
            (_paymentMethod != 'Cash' || _cashReceived >= _payableAmount));
    return SizedBox(
      width: double.infinity,
      height: height,
      child: FilledButton.icon(
        onPressed: _cart.isEmpty || _isCheckingOut || !paymentCanComplete
            ? null
            : _checkout,
        icon: _isCheckingOut
            ? const SizedBox(
                width: 18,
                height: 18,
                child: ModernLoadingIndicator(strokeWidth: 2),
              )
            : showIcon
            ? const Icon(Icons.point_of_sale)
            : const SizedBox.shrink(),
        label: Text(
          _isCheckingOut ? 'Saving...' : 'Pay Now',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _suspendButton({required double height}) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: OutlinedButton.icon(
        onPressed: _cart.isEmpty || _isCheckingOut ? null : _suspendCart,
        icon: const Icon(Icons.pause),
        label: const Text('Suspend'),
      ),
    );
  }
}

class _PaymentResult {
  final double paidAmount;
  final double changeAmount;
  final bool isCredit;
  final String? customerName;

  const _PaymentResult({
    required this.paidAmount,
    required this.changeAmount,
    required this.isCredit,
    this.customerName,
  });
}

class _PaymentSummaryLine extends StatelessWidget {
  final String label;
  final String value;

  const _PaymentSummaryLine(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

enum _VoiceSearchTarget { product, customer }

class _PosCustomer {
  final String id;
  final String name;
  final String phone;
  final List<String> aliases;

  const _PosCustomer({
    required this.id,
    required this.name,
    required this.phone,
    required this.aliases,
  });

  factory _PosCustomer.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final rawAliases = data['aliases'];
    final aliases = rawAliases is Iterable
        ? rawAliases
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toList()
        : (rawAliases?.toString() ?? '')
              .split(',')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList();
    return _PosCustomer(
      id: doc.id,
      name: (data['name'] as String? ?? 'Customer').trim(),
      phone: (data['phone'] as String? ?? '').trim(),
      aliases: aliases,
    );
  }
}

class _BarcodeScannerPage extends StatefulWidget {
  final ValueChanged<String> onCodeDetected;

  const _BarcodeScannerPage({required this.onCodeDetected});

  @override
  State<_BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<_BarcodeScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  final Map<String, DateTime> _lastScannedAt = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final now = DateTime.now();

    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue?.trim();
      if (code == null || code.isEmpty) continue;

      final lastScan = _lastScannedAt[code];
      if (lastScan != null && now.difference(lastScan).inMilliseconds < 1200) {
        continue;
      }

      _lastScannedAt[code] = now;
      widget.onCodeDetected(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Product'),
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
                  'Point the camera at a product barcode or QR code. Each successful scan adds one item to the cart.',
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

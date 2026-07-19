import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'models.dart';
import 'notification_inbox_page.dart';

class CustomerRegistrationPage extends StatefulWidget {
  const CustomerRegistrationPage({super.key});

  @override
  State<CustomerRegistrationPage> createState() =>
      _CustomerRegistrationPageState();
}

class _CustomerRegistrationPageState extends State<CustomerRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _password = TextEditingController();
  bool _saving = false;
  GeoPoint? _location;

  Future<void> _useGps() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable location services.')),
        );
      }
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }
    final position = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() {
        _location = GeoPoint(position.latitude, position.longitude);
        if (_address.text.trim().isEmpty) _address.text = 'Pinned GPS location';
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final credential = await auth.FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _email.text.trim(),
            password: _password.text,
          );
      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .set({
            'id': credential.user!.uid,
            'name': _name.text.trim(),
            'email': _email.text.trim(),
            'phone': _phone.text.trim(),
            'address': _address.text.trim(),
            if (_location != null) 'location': _location,
            'role': UserRole.customer,
            'isActive': true,
            'createdAt': FieldValue.serverTimestamp(),
          });
      if (mounted) Navigator.pop(context);
    } on auth.FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Registration failed.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create customer account')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  _field(_name, 'Full name'),
                  _field(_email, 'Email', type: TextInputType.emailAddress),
                  _field(_phone, 'Phone number', type: TextInputType.phone),
                  _field(_address, 'Delivery address'),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _useGps,
                      icon: const Icon(Icons.my_location),
                      label: Text(
                        _location == null
                            ? 'Use current GPS location'
                            : 'GPS location pinned',
                      ),
                    ),
                  ),
                  _field(_password, 'Password', password: true, minLength: 6),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _saving ? null : _register,
                      child: Text(_saving ? 'Creating account...' : 'Register'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? type,
    bool password = false,
    int minLength = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: type,
        obscureText: password,
        decoration: InputDecoration(labelText: label),
        validator: (value) => (value?.trim().length ?? 0) < minLength
            ? minLength == 1
                  ? 'Required'
                  : 'Use at least $minLength characters'
            : null,
      ),
    );
  }
}

class CustomerMarketplace extends StatefulWidget {
  final User customer;
  const CustomerMarketplace({super.key, required this.customer});

  @override
  State<CustomerMarketplace> createState() => _CustomerMarketplaceState();
}

class _CustomerMarketplaceState extends State<CustomerMarketplace> {
  final Map<String, _CartLine> _cart = {};
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _ShopPage(
        customer: widget.customer,
        cart: _cart,
        changed: () => setState(() {}),
      ),
      _CartPage(
        customer: widget.customer,
        cart: _cart,
        changed: () => setState(() {}),
      ),
      _CustomerOrdersPage(customer: widget.customer),
      _CustomerProfilePage(customer: widget.customer),
    ];
    final cartCount = _cart.values.fold<int>(
      0,
      (count, line) => count + line.quantity,
    );
    final navigationDestinations = [
      const NavigationDestination(icon: Icon(Icons.storefront), label: 'Shop'),
      NavigationDestination(
        icon: Badge(
          isLabelVisible: _cart.isNotEmpty,
          label: Text('$cartCount'),
          child: const Icon(Icons.shopping_cart),
        ),
        label: 'Cart',
      ),
      const NavigationDestination(
        icon: Icon(Icons.local_shipping),
        label: 'Orders',
      ),
      const NavigationDestination(icon: Icon(Icons.person), label: 'Account'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 850;
        return Scaffold(
          body: Row(
            children: [
              if (isDesktop)
                NavigationRail(
                  extended: constraints.maxWidth >= 1100,
                  minExtendedWidth: 230,
                  selectedIndex: _index,
                  onDestinationSelected: (value) =>
                      setState(() => _index = value),
                  leading: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shopping_bag,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        if (constraints.maxWidth >= 1100) ...[
                          const SizedBox(width: 10),
                          const Text(
                            'Marketplace',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ],
                    ),
                  ),
                  destinations: [
                    const NavigationRailDestination(
                      icon: Icon(Icons.storefront_outlined),
                      selectedIcon: Icon(Icons.storefront),
                      label: Text('Shop'),
                    ),
                    NavigationRailDestination(
                      icon: Badge(
                        isLabelVisible: _cart.isNotEmpty,
                        label: Text('$cartCount'),
                        child: const Icon(Icons.shopping_cart_outlined),
                      ),
                      selectedIcon: Badge(
                        isLabelVisible: _cart.isNotEmpty,
                        label: Text('$cartCount'),
                        child: const Icon(Icons.shopping_cart),
                      ),
                      label: const Text('Cart'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.local_shipping_outlined),
                      selectedIcon: Icon(Icons.local_shipping),
                      label: Text('Orders'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.person_outline),
                      selectedIcon: Icon(Icons.person),
                      label: Text('Account'),
                    ),
                  ],
                ),
              if (isDesktop) const VerticalDivider(width: 1),
              Expanded(
                child: IndexedStack(index: _index, children: pages),
              ),
            ],
          ),
          bottomNavigationBar: isDesktop
              ? null
              : NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (value) =>
                      setState(() => _index = value),
                  destinations: navigationDestinations,
                ),
        );
      },
    );
  }
}

class _ShopPage extends StatefulWidget {
  final User customer;
  final Map<String, _CartLine> cart;
  final VoidCallback changed;
  const _ShopPage({
    required this.customer,
    required this.cart,
    required this.changed,
  });

  @override
  State<_ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<_ShopPage> {
  String _query = '';
  String? _category;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketplace'),
        actions: [
          NotificationBellButton(user: widget.customer),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => auth.FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('products').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!.docs
              .where((doc) => doc.data()['isAvailableOnline'] == true)
              .map((doc) => Product.fromMap({'id': doc.id, ...doc.data()}))
              .where((product) => product.stockQuantity > 0)
              .toList();
          final categories = all.map((p) => p.category).toSet().toList()
            ..sort();
          final products = all.where((product) {
            final matchesCategory =
                _category == null || product.category == _category;
            final text =
                '${product.name} ${product.category} ${product.brandName ?? ''}'
                    .toLowerCase();
            return matchesCategory && text.contains(_query.toLowerCase());
          }).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    hintText: 'Search products and brands',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  children: [
                    ChoiceChip(
                      label: const Text('All categories'),
                      selected: _category == null,
                      onSelected: (_) => setState(() => _category = null),
                    ),
                    ...categories.map(
                      (category) => Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          label: Text(category),
                          selected: _category == category,
                          onSelected: (_) =>
                              setState(() => _category = category),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: products.isEmpty
                    ? const Center(child: Text('No online products found.'))
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 280,
                              mainAxisExtent: 330,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                            ),
                        itemCount: products.length,
                        itemBuilder: (context, index) {
                          final product = products[index];
                          final imageUrl =
                              snapshot.data!.docs
                                      .firstWhere((doc) => doc.id == product.id)
                                      .data()['imageUrl']
                                  as String?;
                          return _ProductCard(
                            product: product,
                            imageUrl: imageUrl,
                            onView: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _ProductDetailsPage(
                                  product: product,
                                  imageUrl: imageUrl,
                                  customer: widget.customer,
                                ),
                              ),
                            ),
                            onAdd: () {
                              final line = widget.cart[product.id];
                              if (line == null) {
                                widget.cart[product.id] = _CartLine(
                                  product: product,
                                  imageUrl: imageUrl,
                                );
                              } else if (line.quantity <
                                  product.stockQuantity) {
                                line.quantity++;
                              }
                              widget.changed();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Added to cart.')),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final String? imageUrl;
  final VoidCallback onView;
  final VoidCallback onAdd;
  const _ProductCard({
    required this.product,
    required this.imageUrl,
    required this.onView,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onView,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: imageUrl == null
                    ? const ColoredBox(
                        color: Color(0xFF242424),
                        child: Icon(Icons.inventory_2, size: 72),
                      )
                    : Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image, size: 60),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${product.shopName ?? 'Shop'}${product.lipaNumber == null ? '' : ' • Lipa: ${product.lipaNumber}'}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    product.description ?? product.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _money(product.price),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton.filled(
                        tooltip: 'Add to cart',
                        onPressed: onAdd,
                        icon: const Icon(Icons.add_shopping_cart),
                      ),
                    ],
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

class _ProductDetailsPage extends StatelessWidget {
  final Product product;
  final String? imageUrl;
  final User customer;

  const _ProductDetailsPage({
    required this.product,
    required this.imageUrl,
    required this.customer,
  });

  Future<void> _openReviewEditor(BuildContext context) async {
    final reviewId = '${product.id}_${customer.id}';
    final existing = await FirebaseFirestore.instance
        .collection('product_reviews')
        .doc(reviewId)
        .get();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _ReviewDialog(
        product: product,
        customer: customer,
        reviewId: reviewId,
        existing: existing.data(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(product.name)),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('product_reviews')
            .snapshots(),
        builder: (context, snapshot) {
          final reviews =
              (snapshot.data?.docs ?? const [])
                  .where((doc) => doc.data()['productId'] == product.id)
                  .map((doc) => doc.data())
                  .toList()
                ..sort(
                  (a, b) =>
                      _date(b['updatedAt']).compareTo(_date(a['updatedAt'])),
                );
          final average = reviews.isEmpty
              ? 0.0
              : reviews.fold<double>(
                      0,
                      (total, review) =>
                          total + ((review['rating'] as num?)?.toDouble() ?? 0),
                    ) /
                    reviews.length;

          return LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 850;
              final details = _ProductDetails(
                product: product,
                imageUrls: product.imageUrls.isNotEmpty
                    ? product.imageUrls
                    : [?imageUrl],
                average: average,
                reviewCount: reviews.length,
                onReview: () => _openReviewEditor(context),
              );
              final reviewList = _ReviewList(
                reviews: reviews,
                embedded: !desktop,
              );
              return desktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: details),
                        const VerticalDivider(width: 1),
                        Expanded(child: reviewList),
                      ],
                    )
                  : ListView(children: [details, const Divider(), reviewList]);
            },
          );
        },
      ),
    );
  }
}

class _ProductDetails extends StatelessWidget {
  final Product product;
  final List<String> imageUrls;
  final double average;
  final int reviewCount;
  final VoidCallback onReview;

  const _ProductDetails({
    required this.product,
    required this.imageUrls,
    required this.average,
    required this.reviewCount,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(20),
      children: [
        SizedBox(
          height: 300,
          child: imageUrls.isEmpty
              ? const ColoredBox(
                  color: Color(0xFF242424),
                  child: Center(child: Icon(Icons.inventory_2, size: 100)),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: imageUrls.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) => ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      imageUrls[index],
                      width: MediaQuery.sizeOf(context).width.clamp(280, 620),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox(
                        width: 280,
                        child: Icon(Icons.broken_image, size: 80),
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 18),
        Text(
          '${product.shopName ?? 'Shop'}${product.lipaNumber == null ? '' : ' • Lipa: ${product.lipaNumber}'}',
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
        Text(product.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            _RatingStars(rating: average),
            const SizedBox(width: 8),
            Text(
              reviewCount == 0
                  ? 'No reviews yet'
                  : '${average.toStringAsFixed(1)} ($reviewCount reviews)',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _money(product.price),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        Text(product.description ?? 'No product description provided.'),
        const SizedBox(height: 12),
        Text('Category: ${product.category}'),
        Text('Brand: ${product.brandName ?? 'Not specified'}'),
        Text('Available: ${product.stockQuantity.toStringAsFixed(0)}'),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onReview,
          icon: const Icon(Icons.rate_review),
          label: const Text('Rate or review this product'),
        ),
      ],
    );
  }
}

class _ReviewList extends StatelessWidget {
  final List<Map<String, dynamic>> reviews;
  final bool embedded;
  const _ReviewList({required this.reviews, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    if (reviews.isEmpty) {
      return const Center(
        child: Text('Be the first customer to review this product.'),
      );
    }
    return ListView.separated(
      shrinkWrap: embedded,
      physics: embedded ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.all(20),
      itemCount: reviews.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        final review = reviews[index];
        final customerName = review['customerName'] as String? ?? 'Customer';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            child: Text(
              customerName.isEmpty ? '?' : customerName[0].toUpperCase(),
            ),
          ),
          title: Text(customerName),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RatingStars(
                rating: (review['rating'] as num?)?.toDouble() ?? 0,
                size: 18,
              ),
              if ((review['comment'] as String? ?? '').isNotEmpty)
                Text(review['comment'] as String),
              Text(
                _formatDate(review['updatedAt']),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RatingStars extends StatelessWidget {
  final double rating;
  final double size;
  const _RatingStars({required this.rating, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (index) => Icon(
          index < rating.round() ? Icons.star : Icons.star_border,
          color: Colors.amber,
          size: size,
        ),
      ),
    );
  }
}

class _ReviewDialog extends StatefulWidget {
  final Product product;
  final User customer;
  final String reviewId;
  final Map<String, dynamic>? existing;

  const _ReviewDialog({
    required this.product,
    required this.customer,
    required this.reviewId,
    required this.existing,
  });

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  late int _rating;
  late final TextEditingController _comment;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rating = (widget.existing?['rating'] as num?)?.toInt() ?? 5;
    _comment = TextEditingController(
      text: widget.existing?['comment'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('product_reviews')
          .doc(widget.reviewId)
          .set({
            'id': widget.reviewId,
            'productId': widget.product.id,
            'businessId': widget.product.businessId,
            'customerId': widget.customer.id,
            'customerName': widget.customer.name,
            'rating': _rating,
            'comment': _comment.text.trim(),
            if (widget.existing == null)
              'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save review: $error')),
        );
      }
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Review ${widget.product.name}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                5,
                (index) => IconButton(
                  tooltip: '${index + 1} stars',
                  onPressed: _saving
                      ? null
                      : () => setState(() => _rating = index + 1),
                  icon: Icon(
                    index < _rating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 32,
                  ),
                ),
              ),
            ),
            TextField(
              controller: _comment,
              minLines: 3,
              maxLines: 6,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Your review (optional)',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Submit review'),
        ),
      ],
    );
  }
}

class _CartPage extends StatefulWidget {
  final User customer;
  final Map<String, _CartLine> cart;
  final VoidCallback changed;
  const _CartPage({
    required this.customer,
    required this.cart,
    required this.changed,
  });

  @override
  State<_CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<_CartPage> {
  bool _checkingOut = false;
  double get _total => widget.cart.values.fold(
    0,
    (total, line) => total + line.product.price * line.quantity,
  );

  Future<void> _checkout() async {
    if (widget.cart.isEmpty || _checkingOut) return;
    final checkoutLines = widget.cart.values
        .map(
          (line) => _CheckoutLine(
            product: line.product,
            imageUrl: line.imageUrl,
            quantity: line.quantity,
          ),
        )
        .toList(growable: false);
    final linesByShop = <String, List<_CheckoutLine>>{};
    for (final line in checkoutLines) {
      final shopId = line.product.businessId ?? 'default_business';
      linesByShop.putIfAbsent(shopId, () => []).add(line);
    }

    final firestore = FirebaseFirestore.instance;
    final shops = <String, Map<String, dynamic>>{};
    final requiredPayments = <String, double>{};
    final paymentMessages = <String>[];
    for (final entry in linesByShop.entries) {
      final shopDoc = await firestore
          .collection('businesses')
          .doc(entry.key)
          .get();
      final shop = shopDoc.data() ?? const <String, dynamic>{};
      shops[entry.key] = shop;
      final defaultTiming =
          shop['onlinePaymentTiming'] as String? ?? 'before_order';
      final defaultAmount = shop['onlinePaymentAmount'] as String? ?? 'full';
      final partialPercent =
          ((shop['onlinePartialPercent'] as num?)?.toDouble() ?? 50)
              .clamp(1, 100)
              .toDouble();
      final requiredNow = entry.value.fold<double>(0, (total, line) {
        final timing = line.product.paymentTiming == 'business_default'
            ? defaultTiming
            : line.product.paymentTiming;
        final policy = line.product.paymentAmountPolicy == 'business_default'
            ? defaultAmount
            : line.product.paymentAmountPolicy;
        if (timing != 'before_order') return total;
        final lineTotal =
            line.product.price * line.quantity +
            (line.product.freeShipping ? 0 : line.product.shippingFee);
        return total +
            (policy == 'partial'
                ? lineTotal * partialPercent / 100
                : lineTotal);
      });
      requiredPayments[entry.key] = requiredNow;
      if (requiredNow > 0) {
        final shopName =
            shop['name'] ?? entry.value.first.product.shopName ?? 'Shop';
        paymentMessages.add(
          '$shopName: ${_money(requiredNow)} '
          '(Lipa number: ${shop['lipaNumber'] ?? 'Not configured'})',
        );
      }
    }
    if (paymentMessages.isNotEmpty) {
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Pay before placing order'),
          content: Text(
            '${paymentMessages.join('\n')}\n\nContinue only after making each payment.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('I have paid'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
    }
    setState(() => _checkingOut = true);
    try {
      final customerDoc = await firestore
          .collection('users')
          .doc(widget.customer.id)
          .get();
      final orderRefs = {
        for (final shopId in linesByShop.keys)
          shopId: firestore.collection('customer_orders').doc(),
      };
      await firestore.runTransaction((transaction) async {
        final snapshots = <String, DocumentSnapshot<Map<String, dynamic>>>{};
        for (final line in checkoutLines) {
          final ref = firestore.collection('products').doc(line.product.id);
          snapshots[line.product.id] = await transaction.get(ref);
        }
        for (final line in checkoutLines) {
          final snapshot = snapshots[line.product.id]!;
          final available =
              (snapshot.data()?['stockQuantity'] as num?)?.toDouble() ?? 0;
          if (!snapshot.exists || available < line.quantity) {
            throw Exception('${line.product.name} no longer has enough stock.');
          }
          transaction.update(snapshot.reference, {
            'stockQuantity': available - line.quantity,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        for (final entry in linesByShop.entries) {
          final shopId = entry.key;
          final shopLines = entry.value;
          final shop = shops[shopId]!;
          final orderRef = orderRefs[shopId]!;
          final subtotal = shopLines.fold<double>(
            0,
            (total, line) => total + line.product.price * line.quantity,
          );
          final shippingFee = shopLines.fold<double>(
            0,
            (total, line) =>
                total +
                (line.product.freeShipping ? 0 : line.product.shippingFee),
          );
          final orderTotal = subtotal + shippingFee;
          final requiredNow = requiredPayments[shopId] ?? 0;
          transaction.set(orderRef, {
            'id': orderRef.id,
            'customerId': widget.customer.id,
            'customerName': widget.customer.name,
            'customerEmail': widget.customer.email,
            'customerPhone': customerDoc.data()?['phone'] ?? '',
            'status': 'placed',
            'deliveryAddress': customerDoc.data()?['address'] ?? '',
            'deliveryLocation': customerDoc.data()?['location'],
            'paymentTiming':
                shop['onlinePaymentTiming'] as String? ?? 'before_order',
            'paymentAmountPolicy':
                shop['onlinePaymentAmount'] as String? ?? 'full',
            'requiredPayment': requiredNow,
            'paidAmount': requiredNow,
            'paymentStatus': requiredNow >= orderTotal
                ? 'paid'
                : (requiredNow > 0 ? 'partial' : 'due_on_delivery'),
            'lipaNumber': shop['lipaNumber'],
            'paymentBusinessName':
                shop['name'] ?? shopLines.first.product.shopName,
            'subtotal': subtotal,
            'shippingFee': shippingFee,
            'total': orderTotal,
            'shopIds': [shopId],
            'shopNames': [
              shop['name'] ?? shopLines.first.product.shopName ?? 'Shop',
            ],
            'items': shopLines
                .map(
                  (line) => {
                    'productId': line.product.id,
                    'name': line.product.name,
                    'shopName': line.product.shopName,
                    'businessId': shopId,
                    'quantity': line.quantity,
                    'unitPrice': line.product.price,
                    'imageUrl': line.imageUrl,
                  },
                )
                .toList(),
            'statusHistory': [
              {'status': 'placed', 'at': Timestamp.now()},
            ],
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
      for (final line in checkoutLines) {
        widget.cart.remove(line.product.id);
      }
      if (!mounted) return;
      widget.changed();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${linesByShop.length} shop order${linesByShop.length == 1 ? '' : 's'} placed successfully.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Checkout failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.cart.values.toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopping cart'),
        actions: [NotificationBellButton(user: widget.customer)],
      ),
      body: lines.isEmpty
          ? const Center(child: Text('Your cart is empty.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: lines.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, index) {
                final line = lines[index];
                return ListTile(
                  title: Text(line.product.name),
                  subtitle: Text(
                    '${line.product.shopName ?? 'Shop'} • ${_money(line.product.price)} each',
                  ),
                  leading: line.imageUrl == null
                      ? const CircleAvatar(child: Icon(Icons.inventory_2))
                      : CircleAvatar(
                          backgroundImage: NetworkImage(line.imageUrl!),
                        ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () {
                          if (line.quantity == 1) {
                            widget.cart.remove(line.product.id);
                          } else {
                            line.quantity--;
                          }
                          widget.changed();
                        },
                        icon: const Icon(Icons.remove),
                      ),
                      Text('${line.quantity}'),
                      IconButton(
                        onPressed: line.quantity >= line.product.stockQuantity
                            ? null
                            : () {
                                line.quantity++;
                                widget.changed();
                              },
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                );
              },
            ),
      bottomNavigationBar: widget.cart.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _checkingOut ? null : _checkout,
                  icon: const Icon(Icons.lock),
                  label: Text(
                    _checkingOut
                        ? 'Placing order...'
                        : 'Place order • ${_money(_total)}',
                  ),
                ),
              ),
            ),
    );
  }
}

class _CustomerOrdersPage extends StatelessWidget {
  final User customer;
  const _CustomerOrdersPage({required this.customer});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My orders'),
        actions: [NotificationBellButton(user: customer)],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('customer_orders')
            .where('customerId', isEqualTo: customer.id)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs.toList()
            ..sort(
              (a, b) => _date(
                b.data()['createdAt'],
              ).compareTo(_date(a.data()['createdAt'])),
            );
          if (docs.isEmpty) return const Center(child: Text('No orders yet.'));
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final status = data['status'] as String? ?? 'placed';
              return Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(_statusIcon(status))),
                  title: Text(
                    'Order #${docs[index].id.substring(0, 8).toUpperCase()}',
                  ),
                  subtitle: Text(
                    '${(data['shopNames'] as List?)?.join(', ') ?? 'Shop'}\n${_formatDate(data['createdAt'])}',
                  ),
                  isThreeLine: true,
                  trailing: status == 'delivered'
                      ? IconButton(
                          tooltip: 'Receipt',
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _CustomerReceiptPage(
                                orderId: docs[index].id,
                                data: data,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.receipt_long),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _money((data['total'] as num?) ?? 0),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(_statusLabel(status)),
                          ],
                        ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _OrderTrackingPage(
                        orderId: docs[index].id,
                        data: data,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CustomerReceiptPage extends StatelessWidget {
  final String orderId;
  final Map<String, dynamic> data;
  const _CustomerReceiptPage({required this.orderId, required this.data});

  Future<void> _print() async {
    final document = pw.Document();
    final items = (data['items'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    document.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Text(
            'DELIVERY RECEIPT',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text('Order: ${orderId.toUpperCase()}'),
          pw.Text('Customer: ${data['customerName'] ?? ''}'),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const ['Product', 'Qty', 'Price'],
            data: items
                .map(
                  (item) => [
                    item['name'],
                    '${item['quantity']}',
                    _money((item['unitPrice'] as num?) ?? 0),
                  ],
                )
                .toList(),
          ),
          pw.SizedBox(height: 12),
          pw.Text('Shipping: ${_money((data['shippingFee'] as num?) ?? 0)}'),
          pw.Text(
            'TOTAL: ${_money((data['total'] as num?) ?? 0)}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.Text('Status: Delivered'),
        ],
      ),
    );
    await Printing.layoutPdf(
      onLayout: (_) => document.save(),
      name: 'delivery_receipt_$orderId.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = (data['items'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery receipt'),
        actions: [IconButton(onPressed: _print, icon: const Icon(Icons.print))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Order #${orderId.substring(0, 8).toUpperCase()}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          ...items.map(
            (item) => ListTile(
              title: Text(item['name'] ?? 'Product'),
              subtitle: Text(
                '${item['quantity']} × ${_money((item['unitPrice'] as num?) ?? 0)}',
              ),
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Shipping'),
            trailing: Text(_money((data['shippingFee'] as num?) ?? 0)),
          ),
          ListTile(
            title: const Text(
              'Total',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            trailing: Text(
              _money((data['total'] as num?) ?? 0),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          FilledButton.icon(
            onPressed: _print,
            icon: const Icon(Icons.receipt_long),
            label: const Text('Print or save receipt'),
          ),
        ],
      ),
    );
  }
}

class _OrderTrackingPage extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic> data;
  const _OrderTrackingPage({required this.orderId, required this.data});

  @override
  State<_OrderTrackingPage> createState() => _OrderTrackingPageState();
}

class _OrderTrackingPageState extends State<_OrderTrackingPage> {
  bool _uploading = false;

  Future<void> _rateDelivery(Map<String, dynamic> data) async {
    var rating = 5;
    final comment = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Rate ${data['deliveryBoyName'] ?? 'delivery person'}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (index) => IconButton(
                    onPressed: () => setDialogState(() => rating = index + 1),
                    icon: Icon(
                      index < rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                    ),
                  ),
                ),
              ),
              TextField(
                controller: comment,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Comment (optional)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    await FirebaseFirestore.instance
        .collection('delivery_ratings')
        .doc('${widget.orderId}_${data['customerId']}')
        .set({
          'orderId': widget.orderId,
          'deliveryBoyId': data['deliveryBoyId'],
          'deliveryBoyName': data['deliveryBoyName'],
          'customerId': data['customerId'],
          'customerName': data['customerName'],
          'rating': rating,
          'comment': comment.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> _confirmDelivery() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 75,
      maxWidth: 1400,
    );
    if (image == null) return;
    setState(() => _uploading = true);
    final ref = FirebaseStorage.instance.ref(
      'delivery_proofs/${widget.orderId}.jpg',
    );
    await ref.putFile(File(image.path));
    final url = await ref.getDownloadURL();
    final firestore = FirebaseFirestore.instance;
    final orderRef = firestore
        .collection('customer_orders')
        .doc(widget.orderId);
    await orderRef.update({
      'status': 'awaiting_owner_confirmation',
      'customerDeliveryConfirmed': true,
      'deliveryProofUrl': url,
      'customerConfirmedAt': FieldValue.serverTimestamp(),
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'awaiting_owner_confirmation', 'at': Timestamp.now()},
      ]),
    });
    if (mounted) setState(() => _uploading = false);
  }

  @override
  Widget build(BuildContext context) {
    const stages = [
      'confirmed',
      'processing',
      'shipped',
      'out_for_delivery',
      'awaiting_customer_confirmation',
      'awaiting_owner_confirmation',
      'delivered',
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('Order #${widget.orderId.substring(0, 8).toUpperCase()}'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('customer_orders')
            .doc(widget.orderId)
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? widget.data;
          final status = data['status'] as String? ?? 'placed';
          final active = stages.indexOf(status);
          final items = (data['items'] as List? ?? const [])
              .cast<Map<String, dynamic>>();
          final driverLocation = data['driverLocation'] as GeoPoint?;
          final route = (data['driverRoute'] as List? ?? const []);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Track shipment',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (status == 'out_for_delivery' ||
                  data['deliveryStarted'] == true)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.delivery_dining),
                    title: Text(
                      '${data['deliveryBoyName'] ?? 'Delivery person'} is on the way',
                    ),
                    subtitle: Text(
                      driverLocation == null
                          ? 'Waiting for live location…'
                          : '${data['deliveryAddress'] ?? 'Delivery location'}\nRoute updates: ${route.length}',
                    ),
                    trailing: driverLocation == null
                        ? null
                        : IconButton(
                            tooltip: 'Open live location in Maps',
                            onPressed: () => _openInMaps(
                              driverLocation,
                              '${data['deliveryBoyName'] ?? 'Delivery person'} live location',
                            ),
                            icon: const Icon(Icons.map),
                          ),
                  ),
                ),
              if (status == 'awaiting_customer_confirmation')
                FilledButton.icon(
                  onPressed: _uploading ? null : _confirmDelivery,
                  icon: const Icon(Icons.add_a_photo),
                  label: Text(
                    _uploading
                        ? 'Uploading proof…'
                        : 'Confirm delivery with product photo',
                  ),
                ),
              if (status == 'awaiting_owner_confirmation')
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.hourglass_top),
                    title: Text('Photo sent to the owner'),
                    subtitle: Text(
                      'Delivery will complete after the owner reviews and confirms the photo.',
                    ),
                  ),
                ),
              if (status == 'delivered' && data['deliveryBoyId'] != null)
                OutlinedButton.icon(
                  onPressed: () => _rateDelivery(data),
                  icon: const Icon(Icons.star),
                  label: const Text('Rate delivery person'),
                ),
              if ((data['paymentStatus'] as String? ?? '') == 'due_on_delivery')
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.payments),
                    title: Text(
                      'Pay on delivery to ${data['paymentBusinessName'] ?? 'Business'}',
                    ),
                    subtitle: Text(
                      'Lipa number: ${data['lipaNumber'] ?? 'Not configured'}',
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              ...stages.indexed.map(
                (entry) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    entry.$1 <= active
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: entry.$1 <= active
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                  ),
                  title: Text(_statusLabel(entry.$2)),
                ),
              ),
              const Divider(),
              Text('Items', style: Theme.of(context).textTheme.titleLarge),
              ...items.map(
                (item) => ListTile(
                  title: Text(item['name'] as String? ?? 'Product'),
                  subtitle: Text('${item['shopName'] ?? 'Shop'}'),
                  trailing: Text(
                    '${item['quantity']} x ${_money((item['unitPrice'] as num?) ?? 0)}',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CustomerProfilePage extends StatelessWidget {
  final User customer;
  const _CustomerProfilePage({required this.customer});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My account'),
        actions: [NotificationBellButton(user: customer)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          CircleAvatar(
            radius: 42,
            child: Text(
              customer.name.isEmpty ? '?' : customer.name[0].toUpperCase(),
              style: const TextStyle(fontSize: 30),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              customer.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Center(child: Text(customer.email)),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            onPressed: () => auth.FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class CustomerOrderManagementPage extends StatelessWidget {
  final User user;
  final VoidCallback? onOpenMenu;
  const CustomerOrderManagementPage({
    super.key,
    required this.user,
    this.onOpenMenu,
  });

  String get _businessId => user.businessId ?? 'default_business';

  Future<void> _setStatus(
    BuildContext context,
    DocumentReference<Map<String, dynamic>> reference,
    String status,
  ) async {
    final current = await reference.get();
    final driverId = current.data()?['deliveryBoyId'] as String?;
    final batch = FirebaseFirestore.instance.batch();
    batch.update(reference, {
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      'statusHistory': FieldValue.arrayUnion([
        {'status': status, 'at': Timestamp.now(), 'updatedBy': user.id},
      ]),
    });
    if (status == 'cancelled' && driverId != null) {
      batch.update(
        FirebaseFirestore.instance.collection('users').doc(driverId),
        {'deliveryAvailable': true, 'activeOrderId': FieldValue.delete()},
      );
    }
    await batch.commit();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order marked ${_statusLabel(status)}.')),
      );
    }
  }

  Future<void> _assignDeliveryBoy(
    BuildContext context,
    DocumentReference<Map<String, dynamic>> order,
  ) async {
    final existingOrder = await order.get();
    final previousDriverId = existingOrder.data()?['deliveryBoyId'] as String?;
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('businessId', isEqualTo: _businessId)
        .get();
    final available = snapshot.docs.where((doc) {
      final d = doc.data();
      return d['role'] == UserRole.deliveryBoy &&
          d['deliveryAvailable'] != false;
    }).toList();
    if (!context.mounted) return;
    final selected = await showDialog<QueryDocumentSnapshot<Map<String, dynamic>>>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Unused delivery boys'),
        children: available.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No unassigned delivery boy is available. Add one in User Management.',
                  ),
                ),
              ]
            : available
                  .map(
                    (driver) => SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, driver),
                      child: ListTile(
                        leading: const Icon(Icons.delivery_dining),
                        title: Text(driver.data()['name'] ?? 'Delivery user'),
                      ),
                    ),
                  )
                  .toList(),
      ),
    );
    if (selected == null) return;
    final batch = FirebaseFirestore.instance.batch();
    if (previousDriverId != null && previousDriverId != selected.id) {
      batch.update(
        FirebaseFirestore.instance.collection('users').doc(previousDriverId),
        {'deliveryAvailable': true, 'activeOrderId': FieldValue.delete()},
      );
    }
    batch.update(order, {
      'status': 'shipped',
      'deliveryBoyId': selected.id,
      'deliveryBoyName': selected.data()['name'],
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'shipped', 'at': Timestamp.now(), 'updatedBy': user.id},
      ]),
    });
    batch.update(selected.reference, {
      'deliveryAvailable': false,
      'activeOrderId': order.id,
    });
    await batch.commit();
  }

  Future<void> _reviewAndConfirmDelivery(
    BuildContext context,
    DocumentReference<Map<String, dynamic>> order,
    Map<String, dynamic> data,
  ) async {
    final proofUrl = data['deliveryProofUrl'] as String?;
    if (proofUrl == null || proofUrl.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Review delivery photo'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Image.network(
                    proofUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('The delivery photo could not be loaded.'),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Uploaded by ${data['customerName'] ?? 'customer'}. Confirm only after checking the product in this photo.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.verified),
            label: const Text('Confirm delivery'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final driverId = data['deliveryBoyId'] as String?;
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    batch.update(order, {
      'status': 'delivered',
      'ownerDeliveryConfirmed': true,
      'ownerConfirmedBy': user.id,
      'deliveredAt': FieldValue.serverTimestamp(),
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'delivered', 'at': Timestamp.now(), 'updatedBy': user.id},
      ]),
    });
    if (driverId != null) {
      batch.update(firestore.collection('users').doc(driverId), {
        'deliveryAvailable': true,
        'activeOrderId': FieldValue.delete(),
      });
    }
    await batch.commit();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery confirmed successfully.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const stages = ['confirmed', 'processing', 'shipped'];
    return Scaffold(
      appBar: AppBar(
        leading: onOpenMenu == null
            ? null
            : IconButton(onPressed: onOpenMenu, icon: const Icon(Icons.menu)),
        title: const Text('Online Orders'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('customer_orders')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load orders: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final orders =
              snapshot.data!.docs.where((doc) {
                final shopIds = (doc.data()['shopIds'] as List? ?? const [])
                    .cast<String>();
                return shopIds.contains(_businessId);
              }).toList()..sort(
                (a, b) => _date(
                  b.data()['createdAt'],
                ).compareTo(_date(a.data()['createdAt'])),
              );
          if (orders.isEmpty) {
            return const Center(
              child: Text('No online orders for this business yet.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final order = orders[index];
              final data = order.data();
              final status = data['status'] as String? ?? 'placed';
              final items = (data['items'] as List? ?? const [])
                  .cast<Map<String, dynamic>>()
                  .where((item) => item['businessId'] == _businessId)
                  .toList();
              final driverLocation = data['driverLocation'] as GeoPoint?;
              final routePoints =
                  (data['driverRoute'] as List? ?? const []).length;
              final currentStage = switch (status) {
                'out_for_delivery' ||
                'awaiting_customer_confirmation' ||
                'awaiting_owner_confirmation' ||
                'delivered' => stages.length - 1,
                'cancelled' => stages.length,
                _ => stages.indexOf(status),
              };
              return Card(
                child: ExpansionTile(
                  leading: CircleAvatar(child: Icon(_statusIcon(status))),
                  title: Text(
                    '${data['customerName'] ?? 'Customer'} • ${_money((data['total'] as num?) ?? 0)}',
                  ),
                  subtitle: Text(
                    'Order #${order.id.substring(0, 8).toUpperCase()} • ${_statusLabel(status)}',
                  ),
                  children: [
                    ...items.map(
                      (item) => ListTile(
                        title: Text(item['name'] as String? ?? 'Product'),
                        trailing: Text(
                          '${item['quantity']} × ${_money((item['unitPrice'] as num?) ?? 0)}',
                        ),
                      ),
                    ),
                    if (data['deliveryStarted'] == true)
                      ListTile(
                        leading: const Icon(Icons.route),
                        title: Text(
                          '${data['deliveryBoyName'] ?? 'Delivery person'} is delivering',
                        ),
                        subtitle: Text(
                          driverLocation == null
                              ? 'Waiting for GPS update…'
                              : '${data['deliveryAddress'] ?? 'Delivery location'} • $routePoints route updates',
                        ),
                        trailing: driverLocation == null
                            ? null
                            : IconButton(
                                tooltip: 'Open live location in Maps',
                                onPressed: () => _openInMaps(
                                  driverLocation,
                                  '${data['deliveryBoyName'] ?? 'Delivery person'} live location',
                                ),
                                icon: const Icon(Icons.map),
                              ),
                      ),
                    if (status == 'awaiting_owner_confirmation')
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: FilledButton.icon(
                          onPressed: () => _reviewAndConfirmDelivery(
                            context,
                            order.reference,
                            data,
                          ),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('View photo and confirm delivery'),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...stages.indexed.map(
                            (entry) => ChoiceChip(
                              label: Text(_statusLabel(entry.$2)),
                              selected: currentStage >= entry.$1,
                              onSelected: entry.$1 != currentStage + 1
                                  ? null
                                  : (_) => entry.$2 == 'shipped'
                                        ? _assignDeliveryBoy(
                                            context,
                                            order.reference,
                                          )
                                        : _setStatus(
                                            context,
                                            order.reference,
                                            entry.$2,
                                          ),
                            ),
                          ),
                          if (status == 'shipped')
                            ActionChip(
                              avatar: const Icon(Icons.person_add, size: 18),
                              label: Text(
                                data['deliveryBoyId'] == null
                                    ? 'Assign delivery boy'
                                    : 'Change delivery boy',
                              ),
                              onPressed: () =>
                                  _assignDeliveryBoy(context, order.reference),
                            ),
                          if (status != 'cancelled' && status != 'delivered')
                            ActionChip(
                              avatar: const Icon(
                                Icons.cancel_outlined,
                                size: 18,
                              ),
                              label: const Text('Cancel order'),
                              onPressed: () => _setStatus(
                                context,
                                order.reference,
                                'cancelled',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class DeliveryOrdersPage extends StatefulWidget {
  final User user;
  const DeliveryOrdersPage({super.key, required this.user});

  @override
  State<DeliveryOrdersPage> createState() => _DeliveryOrdersPageState();
}

class _DeliveryOrdersPageState extends State<DeliveryOrdersPage> {
  StreamSubscription<Position>? _locationSubscription;

  @override
  void initState() {
    super.initState();
    _resumeActiveDelivery();
  }

  Future<void> _resumeActiveDelivery() async {
    final active = await FirebaseFirestore.instance
        .collection('customer_orders')
        .where('deliveryBoyId', isEqualTo: widget.user.id)
        .where('status', isEqualTo: 'out_for_delivery')
        .limit(1)
        .get();
    if (active.docs.isNotEmpty && await _ensureLocation()) {
      await _beginTracking(active.docs.first.reference);
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<bool> _ensureLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<void> _start(DocumentReference<Map<String, dynamic>> order) async {
    if (!await _ensureLocation()) return;
    await order.update({
      'status': 'out_for_delivery',
      'deliveryStarted': true,
      'deliveryStartedAt': FieldValue.serverTimestamp(),
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': 'out_for_delivery',
          'at': Timestamp.now(),
          'updatedBy': widget.user.id,
        },
      ]),
    });
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.id)
        .update({'deliveryAvailable': false, 'activeOrderId': order.id});
    await _beginTracking(order);
  }

  Future<void> _beginTracking(
    DocumentReference<Map<String, dynamic>> order,
  ) async {
    await _locationSubscription?.cancel();
    _locationSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 20,
          ),
        ).listen(
          (position) => order.update({
            'driverLocation': GeoPoint(position.latitude, position.longitude),
            'driverLocationUpdatedAt': FieldValue.serverTimestamp(),
            'driverRoute': FieldValue.arrayUnion([
              {
                'location': GeoPoint(position.latitude, position.longitude),
                'at': Timestamp.now(),
              },
            ]),
          }),
        );
  }

  Future<void> _arrived(DocumentReference<Map<String, dynamic>> order) async {
    await _locationSubscription?.cancel();
    await order.update({
      'status': 'awaiting_customer_confirmation',
      'arrivedAt': FieldValue.serverTimestamp(),
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': 'awaiting_customer_confirmation',
          'at': Timestamp.now(),
          'updatedBy': widget.user.id,
        },
      ]),
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('My Deliveries'),
      actions: [
        NotificationBellButton(user: widget.user),
        IconButton(
          onPressed: () => auth.FirebaseAuth.instance.signOut(),
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('customer_orders')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final businessId = widget.user.businessId ?? 'default_business';
        final orders =
            snapshot.data!.docs
                .where(
                  (doc) =>
                      (doc.data()['shopIds'] as List? ?? const []).contains(
                        businessId,
                      ) &&
                      doc.data()['deliveryBoyId'] != null,
                )
                .toList()
              ..sort((a, b) {
                final mineA = a.data()['deliveryBoyId'] == widget.user.id
                    ? 0
                    : 1;
                final mineB = b.data()['deliveryBoyId'] == widget.user.id
                    ? 0
                    : 1;
                return mineA.compareTo(mineB);
              });
        if (orders.isEmpty) {
          return const Center(child: Text('No delivery is assigned to you.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final order = orders[index];
            final data = order.data();
            final status = data['status'] as String? ?? 'shipped';
            final mine = data['deliveryBoyId'] == widget.user.id;
            final location = data['deliveryLocation'] as GeoPoint?;
            final items = (data['items'] as List? ?? const [])
                .cast<Map<String, dynamic>>();
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order #${order.id.substring(0, 8).toUpperCase()}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${data['customerName'] ?? 'Customer'} • ${data['deliveryAddress'] ?? 'No written address'}',
                    ),
                    if (location != null)
                      OutlinedButton.icon(
                        onPressed: () => _openInMaps(
                          location,
                          data['deliveryAddress'] as String? ??
                              'Customer delivery location',
                        ),
                        icon: const Icon(Icons.map),
                        label: Text(
                          'Open ${data['deliveryAddress'] ?? 'customer location'} in Maps',
                        ),
                      ),
                    Text(
                      'Assigned to: ${data['deliveryBoyName'] ?? 'Delivery person'} • ${_statusLabel(status)}',
                    ),
                    if (mine &&
                        (data['customerPhone'] as String? ?? '').isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse('tel:${data['customerPhone']}'),
                        ),
                        icon: const Icon(Icons.call),
                        label: const Text('Call customer'),
                      ),
                    const Divider(),
                    ...items.map(
                      (item) => Text('${item['quantity']} × ${item['name']}'),
                    ),
                    const SizedBox(height: 14),
                    if (mine && status == 'shipped')
                      FilledButton.icon(
                        onPressed: () => _start(order.reference),
                        icon: const Icon(Icons.navigation),
                        label: const Text('Start delivery'),
                      ),
                    if (mine && status == 'out_for_delivery')
                      FilledButton.icon(
                        onPressed: () => _arrived(order.reference),
                        icon: const Icon(Icons.location_on),
                        label: const Text('I have arrived'),
                      ),
                    if (status == 'awaiting_customer_confirmation')
                      const Text('Waiting for customer photo confirmation…'),
                    if (status == 'awaiting_owner_confirmation')
                      const Text(
                        'Customer uploaded the photo. Waiting for owner confirmation…',
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

class _CartLine {
  final Product product;
  final String? imageUrl;
  int quantity;
  _CartLine({required this.product, required this.imageUrl}) : quantity = 1;
}

class _CheckoutLine {
  final Product product;
  final String? imageUrl;
  final int quantity;

  const _CheckoutLine({
    required this.product,
    required this.imageUrl,
    required this.quantity,
  });
}

String _money(num value) => NumberFormat.currency(
  locale: 'sw_TZ',
  symbol: 'Tsh ',
  decimalDigits: 0,
).format(value);
DateTime _date(dynamic value) => value is Timestamp
    ? value.toDate()
    : DateTime.fromMillisecondsSinceEpoch(0);
String _formatDate(dynamic value) => value is Timestamp
    ? DateFormat('d MMM y, HH:mm').format(value.toDate())
    : 'Pending';
String _statusLabel(String status) => status
    .replaceAll('_', ' ')
    .split(' ')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');
IconData _statusIcon(String status) => switch (status) {
  'delivered' => Icons.check_circle,
  'shipped' => Icons.local_shipping,
  'processing' => Icons.inventory,
  'confirmed' => Icons.thumb_up,
  _ => Icons.receipt_long,
};

Future<void> _openInMaps(GeoPoint location, String label) async {
  final query = Uri.encodeComponent(
    '${location.latitude},${location.longitude} ($label)',
  );
  final uri = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=$query',
  );
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

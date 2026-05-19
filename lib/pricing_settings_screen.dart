import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'models.dart';

class CategoryManagementPage extends StatelessWidget {
  final String businessId;
  const CategoryManagementPage({super.key, required this.businessId});

  Stream<List<ProductCategory>> _categories() {
    return FirebaseFirestore.instance
        .collection('product_categories')
        .orderBy('name')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => ProductCategory.fromMap({'id': doc.id, ...doc.data()}),
              )
              .where((category) => category.businessId == businessId)
              .toList(),
        );
  }

  void _openSheet(BuildContext context, {ProductCategory? category}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _CategorySheet(businessId: businessId, category: category),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Product Categories')),
      body: StreamBuilder<List<ProductCategory>>(
        stream: _categories(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final categories = snapshot.data!;
          if (categories.isEmpty) {
            return const Center(child: Text('No categories yet.'));
          }
          return ListView.separated(
            itemCount: categories.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final category = categories[index];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.category)),
                title: Text(category.name),
                subtitle: Text(
                  category.description.isEmpty
                      ? 'Used by product category dropdowns'
                      : category.description,
                ),
                trailing: IconButton(
                  tooltip: 'Edit category',
                  onPressed: () => _openSheet(context, category: category),
                  icon: const Icon(Icons.edit),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => _CategoryProductsPage(
                      businessId: businessId,
                      category: category,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Category'),
      ),
    );
  }
}

class _CategoryProductsPage extends StatelessWidget {
  final String businessId;
  final ProductCategory category;

  const _CategoryProductsPage({
    required this.businessId,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(category.name)),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('products')
            .orderBy('name')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final products = snapshot.data!.docs.where((doc) {
            return (doc.data()['businessId'] as String? ??
                    'default_business') ==
                businessId;
          }).toList();
          if (products.isEmpty) {
            return const Center(child: Text('No products yet.'));
          }
          return ListView.separated(
            itemCount: products.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final doc = products[index];
              final data = doc.data();
              final isInCategory =
                  (data['category'] as String? ?? 'General') == category.name;
              return CheckboxListTile(
                secondary: const Icon(Icons.inventory_2),
                title: Text(data['name'] as String? ?? 'Product'),
                subtitle: Text(data['barcode'] as String? ?? ''),
                value: isInCategory,
                onChanged: (value) async {
                  await FirebaseFirestore.instance
                      .collection('products')
                      .doc(doc.id)
                      .update({
                        'category': value == true ? category.name : 'General',
                        'updatedAt': FieldValue.serverTimestamp(),
                      });
                },
              );
            },
          );
        },
      ),
    );
  }
}

class PriceGroupManagementPage extends StatelessWidget {
  final String businessId;
  const PriceGroupManagementPage({super.key, required this.businessId});

  Stream<List<PriceGroup>> _groups() {
    return FirebaseFirestore.instance
        .collection('price_groups')
        .orderBy('name')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => PriceGroup.fromMap({'id': doc.id, ...doc.data()}))
              .where((group) => group.businessId == businessId)
              .toList(),
        );
  }

  void _openSheet(BuildContext context, {PriceGroup? group}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _PriceGroupSheet(businessId: businessId, group: group),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Price Groups')),
      body: StreamBuilder<List<PriceGroup>>(
        stream: _groups(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final groups = snapshot.data!;
          if (groups.isEmpty) {
            return const Center(child: Text('No price groups yet.'));
          }
          return ListView.separated(
            itemCount: groups.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final group = groups[index];
              return SwitchListTile(
                secondary: const Icon(Icons.local_offer),
                title: Text(group.name),
                subtitle: Text(
                  '${_typeLabel(group.type)} ${group.value.toStringAsFixed(1)} | ${group.categories.length} categories, ${group.productIds.length} products',
                ),
                value: group.isActive,
                onChanged: (value) => FirebaseFirestore.instance
                    .collection('price_groups')
                    .doc(group.id)
                    .update({'isActive': value}),
                controlAffinity: ListTileControlAffinity.trailing,
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Group'),
      ),
    );
  }
}

class TaxManagementPage extends StatelessWidget {
  final String businessId;
  const TaxManagementPage({super.key, required this.businessId});

  Stream<List<TaxRule>> _taxes() {
    return FirebaseFirestore.instance
        .collection('tax_rules')
        .orderBy('name')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => TaxRule.fromMap({'id': doc.id, ...doc.data()}))
              .where((tax) => tax.businessId == businessId)
              .toList(),
        );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _TaxRuleSheet(businessId: businessId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tax Management')),
      body: StreamBuilder<List<TaxRule>>(
        stream: _taxes(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final taxes = snapshot.data!;
          if (taxes.isEmpty) {
            return const Center(child: Text('No tax rules yet.'));
          }
          return ListView.separated(
            itemCount: taxes.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final tax = taxes[index];
              return SwitchListTile(
                secondary: const Icon(Icons.receipt),
                title: Text(tax.name),
                subtitle: Text(
                  '${tax.rate.toStringAsFixed(1)}% on ${tax.targetType.replaceAll('_', ' ')}',
                ),
                value: tax.isActive,
                onChanged: (value) => FirebaseFirestore.instance
                    .collection('tax_rules')
                    .doc(tax.id)
                    .update({'isActive': value}),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Tax'),
      ),
    );
  }
}

class _CategorySheet extends StatefulWidget {
  final String businessId;
  final ProductCategory? category;
  const _CategorySheet({required this.businessId, this.category});

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _name.text = widget.category?.name ?? '';
    _description.text = widget.category?.description ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    final ref = widget.category == null
        ? FirebaseFirestore.instance.collection('product_categories').doc()
        : FirebaseFirestore.instance
              .collection('product_categories')
              .doc(widget.category!.id);
    await ref.set({
      'id': ref.id,
      'businessId': widget.businessId,
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      title: widget.category == null ? 'Add Category' : 'Edit Category',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(_name, 'Category name'),
          const SizedBox(height: 12),
          _field(_description, 'Description', required: false),
          const SizedBox(height: 16),
          _saveButton(_isSaving, _save),
        ],
      ),
    );
  }
}

class _PriceGroupSheet extends StatefulWidget {
  final String businessId;
  final PriceGroup? group;
  const _PriceGroupSheet({required this.businessId, this.group});

  @override
  State<_PriceGroupSheet> createState() => _PriceGroupSheetState();
}

class _PriceGroupSheetState extends State<_PriceGroupSheet> {
  final _name = TextEditingController();
  final _value = TextEditingController();
  final _categories = TextEditingController();
  final Set<String> _selectedProductIds = {};
  String _type = 'discount_percent';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final group = widget.group;
    if (group == null) return;
    _name.text = group.name;
    _value.text = group.value.toString();
    _type = group.type;
    _categories.text = group.categories.join(', ');
    _selectedProductIds.addAll(group.productIds);
  }

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    _categories.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = double.tryParse(_value.text.trim());
    if (_name.text.trim().isEmpty || value == null) return;
    setState(() => _isSaving = true);
    final ref = widget.group == null
        ? FirebaseFirestore.instance.collection('price_groups').doc()
        : FirebaseFirestore.instance
              .collection('price_groups')
              .doc(widget.group!.id);
    await ref.set({
      'id': ref.id,
      'businessId': widget.businessId,
      'name': _name.text.trim(),
      'type': _type,
      'value': value,
      'categories': _csv(_categories.text),
      'productIds': _selectedProductIds.toList(),
      'isActive': widget.group?.isActive ?? true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _chooseProducts() async {
    final selected = Set<String>.from(_selectedProductIds);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.75,
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Choose Products'),
                    trailing: FilledButton(
                      onPressed: () {
                        setState(() {
                          _selectedProductIds
                            ..clear()
                            ..addAll(selected);
                        });
                        Navigator.pop(context);
                      },
                      child: const Text('Done'),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('products')
                          .orderBy('name')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final products = snapshot.data!.docs.where((doc) {
                          return (doc.data()['businessId'] as String? ??
                                  'default_business') ==
                              widget.businessId;
                        }).toList();
                        if (products.isEmpty) {
                          return const Center(child: Text('No products yet.'));
                        }
                        return ListView.separated(
                          itemCount: products.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final doc = products[index];
                            final data = doc.data();
                            return CheckboxListTile(
                              title: Text(data['name'] as String? ?? 'Product'),
                              subtitle: Text(data['barcode'] as String? ?? ''),
                              value: selected.contains(doc.id),
                              onChanged: (value) {
                                setSheetState(() {
                                  if (value == true) {
                                    selected.add(doc.id);
                                  } else {
                                    selected.remove(doc.id);
                                  }
                                });
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      title: 'Price Group',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(_name, 'Name'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(
              labelText: 'Rule type',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'discount_percent',
                child: Text('Discount percent'),
              ),
              DropdownMenuItem(
                value: 'discount_amount',
                child: Text('Discount amount'),
              ),
              DropdownMenuItem(
                value: 'increase_percent',
                child: Text('Increase percent'),
              ),
              DropdownMenuItem(
                value: 'increase_amount',
                child: Text('Increase amount'),
              ),
            ],
            onChanged: (value) => setState(() => _type = value!),
          ),
          const SizedBox(height: 12),
          _field(
            _value,
            'Value',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          _field(_categories, 'Categories, comma separated', required: false),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _chooseProducts,
            icon: const Icon(Icons.inventory_2),
            label: Text('${_selectedProductIds.length} products selected'),
          ),
          const SizedBox(height: 16),
          _saveButton(_isSaving, _save),
        ],
      ),
    );
  }
}

class _TaxRuleSheet extends StatefulWidget {
  final String businessId;
  const _TaxRuleSheet({required this.businessId});

  @override
  State<_TaxRuleSheet> createState() => _TaxRuleSheetState();
}

class _TaxRuleSheetState extends State<_TaxRuleSheet> {
  final _name = TextEditingController();
  final _rate = TextEditingController();
  final _target = TextEditingController();
  String _targetType = 'category';
  bool _isSaving = false;

  @override
  void dispose() {
    _name.dispose();
    _rate.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final rate = double.tryParse(_rate.text.trim());
    if (_name.text.trim().isEmpty || rate == null) return;
    setState(() => _isSaving = true);
    final ref = FirebaseFirestore.instance.collection('tax_rules').doc();
    final values = _csv(_target.text);
    await ref.set({
      'id': ref.id,
      'businessId': widget.businessId,
      'name': _name.text.trim(),
      'rate': rate,
      'targetType': _targetType,
      'categories': _targetType == 'category' ? values : <String>[],
      'productIds': _targetType == 'product' ? values : <String>[],
      'priceGroupId': _targetType == 'price_group' && values.isNotEmpty
          ? values.first
          : null,
      'isActive': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      title: 'Tax Rule',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(_name, 'Tax name'),
          const SizedBox(height: 12),
          _field(
            _rate,
            'Rate percent',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _targetType,
            decoration: const InputDecoration(
              labelText: 'Apply tax to',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'category', child: Text('Categories')),
              DropdownMenuItem(value: 'product', child: Text('Products')),
              DropdownMenuItem(
                value: 'price_group',
                child: Text('Price group'),
              ),
            ],
            onChanged: (value) => setState(() => _targetType = value!),
          ),
          const SizedBox(height: 12),
          _field(
            _target,
            _targetType == 'price_group'
                ? 'Price group ID'
                : 'Targets, comma separated',
          ),
          const SizedBox(height: 16),
          _saveButton(_isSaving, _save),
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
                    tooltip: 'Close',
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

Widget _saveButton(bool isSaving, VoidCallback onPressed) {
  return SizedBox(
    width: double.infinity,
    height: 48,
    child: FilledButton.icon(
      onPressed: isSaving ? null : onPressed,
      icon: isSaving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.save),
      label: Text(isSaving ? 'Saving...' : 'Save'),
    ),
  );
}

List<String> _csv(String text) {
  return text
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
}

String _typeLabel(String type) {
  return switch (type) {
    'discount_percent' => 'Discount %',
    'discount_amount' => 'Discount amount',
    'increase_percent' => 'Increase %',
    'increase_amount' => 'Increase amount',
    _ => type,
  };
}

import 'package:cloud_firestore/cloud_firestore.dart';

import 'models.dart';

class PricedProduct {
  final double unitPrice;
  final double discountPerUnit;
  final double taxPerUnit;
  final String note;
  final List<String> priceGroupIds;

  const PricedProduct({
    required this.unitPrice,
    required this.discountPerUnit,
    required this.taxPerUnit,
    required this.note,
    required this.priceGroupIds,
  });

  double totalFor(int quantity) =>
      (unitPrice * quantity) - (discountPerUnit * quantity) + (taxPerUnit * quantity);
}

class CommerceRules {
  final List<PriceGroup> priceGroups;
  final List<TaxRule> taxRules;

  const CommerceRules({required this.priceGroups, required this.taxRules});

  static Future<CommerceRules> load(String businessId) async {
    final firestore = FirebaseFirestore.instance;
    final priceSnapshot = await firestore.collection('price_groups').get();
    final taxSnapshot = await firestore.collection('tax_rules').get();

    return CommerceRules(
      priceGroups: priceSnapshot.docs
          .map((doc) => PriceGroup.fromMap({'id': doc.id, ...doc.data()}))
          .where((rule) => rule.businessId == businessId && rule.isActive)
          .toList(),
      taxRules: taxSnapshot.docs
          .map((doc) => TaxRule.fromMap({'id': doc.id, ...doc.data()}))
          .where((rule) => rule.businessId == businessId && rule.isActive)
          .toList(),
    );
  }

  PricedProduct price(Product product) {
    final matchedGroups = priceGroups.where((group) {
      return group.productIds.contains(product.id) ||
          group.categories.contains(product.category);
    }).toList();

    var unitPrice = product.price;
    var discountPerUnit = 0.0;
    final notes = <String>[];

    for (final group in matchedGroups) {
      final value = group.value < 0 ? 0 : group.value;
      switch (group.type) {
        case 'discount_percent':
          final discount = unitPrice * (value / 100);
          discountPerUnit += discount;
          notes.add('${group.name}: -${value.toStringAsFixed(0)}%');
          break;
        case 'discount_amount':
          discountPerUnit += value;
          notes.add('${group.name}: -${value.toStringAsFixed(0)}');
          break;
        case 'increase_percent':
          unitPrice += unitPrice * (value / 100);
          notes.add('${group.name}: +${value.toStringAsFixed(0)}%');
          break;
        case 'increase_amount':
          unitPrice += value;
          notes.add('${group.name}: +${value.toStringAsFixed(0)}');
          break;
      }
    }

    if (discountPerUnit > unitPrice) discountPerUnit = unitPrice;
    final taxableBase = unitPrice - discountPerUnit;
    var taxPerUnit = 0.0;

    for (final rule in taxRules) {
      final applies = rule.targetType == 'price_group'
          ? matchedGroups.any((group) => group.id == rule.priceGroupId)
          : rule.productIds.contains(product.id) ||
              rule.categories.contains(product.category);
      if (!applies) continue;
      taxPerUnit += taxableBase * (rule.rate / 100);
      notes.add('${rule.name}: ${rule.rate.toStringAsFixed(1)}% tax');
    }

    return PricedProduct(
      unitPrice: unitPrice,
      discountPerUnit: discountPerUnit,
      taxPerUnit: taxPerUnit,
      note: notes.join(' | '),
      priceGroupIds: matchedGroups.map((group) => group.id).toList(),
    );
  }
}

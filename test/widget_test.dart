import 'package:flutter_test/flutter_test.dart';
import 'package:point_of_sale/models.dart';

void main() {
  test('product data keeps business and branch ownership', () {
    final product = Product.fromMap({
      'id': 'product-1',
      'name': 'Test product',
      'barcode': '123',
      'price': 2500,
      'stockQuantity': 12,
      'category': 'General',
      'businessId': 'business-1',
      'branchId': 'branch-1',
    });

    expect(product.businessId, 'business-1');
    expect(product.branchId, 'branch-1');
    expect(product.price, 2500);
    expect(product.stockQuantity, 12);
  });
}

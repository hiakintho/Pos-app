import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'database_helper.dart';

class SyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<void> syncData() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.none) return;

    await syncProducts();
    await syncSales();
  }

  Future<void> syncProducts() async {
    final products = await _dbHelper.getAllProducts();
    for (var product in products) {
      if (product.isSynced == 0) {
        try {
          await _firestore
              .collection('products')
              .doc(product.id)
              .set(product.toMap());
          await _dbHelper.updateProductSyncStatus(product.id, 1);
        } catch (e) {
          print('Error syncing product: $e');
        }
      }
    }
  }

  Future<void> syncSales() async {
    final sales = await _dbHelper.getUnsyncedSales();
    for (var sale in sales) {
      try {
        await _firestore.collection('sales').doc(sale.id).set(sale.toMap());
        await _dbHelper.updateSaleSyncStatus(sale.id, 1);
      } catch (e) {
        print('Error syncing sale: $e');
      }
    }
  }
}

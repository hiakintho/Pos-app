import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'database_platform.dart';
import 'models.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static bool _databaseUnavailable = false;
  static final Map<String, Product> _memoryProducts = {};
  static final Map<String, Sale> _memorySales = {};

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    if (_databaseUnavailable) {
      throw StateError('Local SQLite database is unavailable.');
    }
    _database = await _initDB('pos.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    try {
      await configureDatabaseFactory();

      final dbPath = await getDatabasesPath();
      final path = join(dbPath, filePath);

      return await openDatabase(
        path,
        version: 2,
        onCreate: _createDB,
        onUpgrade: _upgradeDB,
      );
    } catch (e) {
      _databaseUnavailable = true;
      throw StateError('Could not open local SQLite database: $e');
    }
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        barcode TEXT NOT NULL,
        price REAL NOT NULL,
        stockQuantity REAL NOT NULL,
        category TEXT NOT NULL,
        expiryDate TEXT,
        isSynced INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE sales (
        id TEXT PRIMARY KEY,
        itemsJson TEXT NOT NULL,
        totalAmount REAL NOT NULL,
        timestamp TEXT NOT NULL,
        branchId TEXT NOT NULL,
        cashierId TEXT NOT NULL,
        paymentMethod TEXT NOT NULL,
        paidAmount REAL DEFAULT 0,
        changeAmount REAL DEFAULT 0,
        discountAmount REAL DEFAULT 0,
        taxAmount REAL DEFAULT 0,
        isCredit INTEGER DEFAULT 0,
        customerName TEXT,
        status TEXT DEFAULT 'completed',
        isSynced INTEGER DEFAULT 0
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      final columns = await db.rawQuery('PRAGMA table_info(sales)');
      final existing = columns.map((column) => column['name']).toSet();

      Future<void> addColumn(String name, String definition) async {
        if (!existing.contains(name)) {
          await db.execute('ALTER TABLE sales ADD COLUMN $name $definition');
        }
      }

      await addColumn('paidAmount', 'REAL DEFAULT 0');
      await addColumn('changeAmount', 'REAL DEFAULT 0');
      await addColumn('discountAmount', 'REAL DEFAULT 0');
      await addColumn('taxAmount', 'REAL DEFAULT 0');
      await addColumn('isCredit', 'INTEGER DEFAULT 0');
      await addColumn('customerName', 'TEXT');
      await addColumn('status', "TEXT DEFAULT 'completed'");
    }
  }

  // Product Operations
  Future<void> insertProduct(Product product) async {
    try {
      final db = await instance.database;
      await db.insert(
        'products',
        product.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      _memoryProducts[product.id] = product;
    }
  }

  Future<List<Product>> getAllProducts() async {
    try {
      final db = await instance.database;
      final result = await db.query('products');
      return result.map((json) => Product.fromMap(json)).toList();
    } catch (_) {
      return _memoryProducts.values.toList();
    }
  }

  Future<void> updateProductSyncStatus(String id, int status) async {
    try {
      final db = await instance.database;
      await db.update(
        'products',
        {'isSynced': status},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (_) {
      final product = _memoryProducts[id];
      if (product != null) {
        _memoryProducts[id] = Product.fromMap({
          ...product.toMap(),
          'isSynced': status,
        });
      }
    }
  }

  Future<void> updateProductStock(String id, double stockQuantity) async {
    try {
      final db = await instance.database;
      await db.update(
        'products',
        {'stockQuantity': stockQuantity, 'isSynced': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (_) {
      final product = _memoryProducts[id];
      if (product != null) {
        _memoryProducts[id] = Product.fromMap({
          ...product.toMap(),
          'stockQuantity': stockQuantity,
          'isSynced': 0,
        });
      }
    }
  }

  // Sale Operations
  Future<void> insertSale(Sale sale) async {
    try {
      final db = await instance.database;
      await db.insert(
        'sales',
        sale.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      _memorySales[sale.id] = sale;
    }
  }

  Future<List<Sale>> getUnsyncedSales() async {
    try {
      final db = await instance.database;
      final result = await db.query(
        'sales',
        where: 'isSynced = ?',
        whereArgs: [0],
      );
      return result.map((json) => Sale.fromMap(json)).toList();
    } catch (_) {
      return _memorySales.values.where((sale) => sale.isSynced == 0).toList();
    }
  }

  Future<void> updateSaleSyncStatus(String id, int status) async {
    try {
      final db = await instance.database;
      await db.update(
        'sales',
        {'isSynced': status},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (_) {
      final sale = _memorySales[id];
      if (sale != null) {
        _memorySales[id] = Sale.fromMap({...sale.toMap(), 'isSynced': status});
      }
    }
  }
}

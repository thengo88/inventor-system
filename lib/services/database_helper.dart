import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/product.dart';
import '../models/user.dart';
import '../models/log_entry.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    // Platform initialization for desktop (Windows/Linux/macOS)
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    String path = join(await getDatabasesPath(), 'inventor_database.db');
    return await openDatabase(
      path,
      version: 2, // Incremented version for new tables
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sku TEXT UNIQUE,
        name TEXT,
        packagingStandard TEXT,
        imageUrl TEXT,
        layoutPosition TEXT,
        customer TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE users(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE,
        password TEXT,
        role TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE logs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT,
        action TEXT,
        details TEXT,
        timestamp TEXT
      )
    ''');

    // Seed initial admin user
    String adminPass = _hashPassword('admin123');
    await db.insert('users', {
      'username': 'admin',
      'password': adminPass,
      'role': 'admin',
    });
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE users(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          username TEXT UNIQUE,
          password TEXT,
          role TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE logs(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          username TEXT,
          action TEXT,
          details TEXT,
          timestamp TEXT
        )
      ''');

      String adminPass = _hashPassword('admin123');
      await db.insert('users', {
        'username': 'admin',
        'password': adminPass,
        'role': 'admin',
      });
    }
  }

  String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  // User Management
  Future<User?> authenticate(String username, String password) async {
    Database db = await database;
    String hashed = _hashPassword(password);
    List<Map<String, dynamic>> maps = await db.query(
      'users',
      where: 'username = ? AND password = ?',
      whereArgs: [username, hashed],
    );
    if (maps.isNotEmpty) {
      return User.fromMap(maps.first);
    }
    return null;
  }

  Future<int> insertUser(User user) async {
    Database db = await database;
    // Hash password before storing
    Map<String, dynamic> userMap = user.toMap();
    userMap['password'] = _hashPassword(user.password);
    return await db.insert('users', userMap);
  }

  Future<List<User>> getUsers() async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query('users');
    return maps.map((map) => User.fromMap(map)).toList();
  }

  Future<int> updateUser(User user) async {
    Database db = await database;
    Map<String, dynamic> userMap = user.toMap();
    // Only hash if password is changed (simplified for this demo)
    userMap['password'] = _hashPassword(user.password);
    return await db.update(
      'users',
      userMap,
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  Future<int> deleteUser(int id) async {
    Database db = await database;
    return await db.delete('users', where: 'id = ?', whereArgs: [id]);
  }

  // Logs
  Future<int> insertLog(LogEntry log) async {
    Database db = await database;
    return await db.insert('logs', log.toMap());
  }

  Future<List<LogEntry>> getLogs() async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query(
      'logs',
      orderBy: 'timestamp DESC',
    );
    return maps.map((map) => LogEntry.fromMap(map)).toList();
  }

  // Product Methods (Existing)
  Future<int> insertProduct(Product product) async {
    Database db = await database;
    return await db.insert(
      'products',
      product.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Product>> getProducts() async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query('products');
    return maps.map((map) => Product.fromMap(map)).toList();
  }

  Future<Product?> getProductBySku(String sku) async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query(
      'products',
      where: 'sku = ?',
      whereArgs: [sku],
    );
    if (maps.isNotEmpty) return Product.fromMap(maps.first);
    return null;
  }

  Future<int> updateProduct(Product product) async {
    Database db = await database;
    return await db.update(
      'products',
      product.toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<int> deleteProduct(int id) async {
    Database db = await database;
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }
}

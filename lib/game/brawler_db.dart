// Plaza Brawler's own SQLite file (plaza_brawler.db) for high scores and feedback (spec 4.6, 4.8).
// Real: sqflite on the phone; tests pass a sqflite_common_ffi factory. Signed fight events live in
// Omni-Core-UI's LocalEventStore database, not here.
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class BrawlerDb {
  BrawlerDb._();

  static const fileName = 'plaza_brawler.db';
  static const version = 1;
  static Database? _db;

  /// Opens (and creates on first use) the database. [factory] and [path] are for tests.
  static Future<Database> open({DatabaseFactory? factory, String? path}) async {
    if (_db != null && factory == null) return _db!;
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: (db, v) async => createTables(db),
      ),
    );
    if (factory == null) _db = db;
    return db;
  }

  static Future<void> createTables(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS high_scores('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, initials TEXT(3) NOT NULL, score INT NOT NULL, '
      'sign TEXT NOT NULL, reached INT NOT NULL, ts INT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS feedback('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, stars INT NOT NULL, tags TEXT NOT NULL, comment TEXT NOT NULL, '
      'mode TEXT NOT NULL, sign TEXT NOT NULL, reached INT NOT NULL, score INT NOT NULL, '
      'app_version TEXT NOT NULL, ts INT NOT NULL)',
    );
  }
}

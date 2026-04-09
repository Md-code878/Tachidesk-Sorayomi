import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DownloadDatabase {
  static final DownloadDatabase instance = DownloadDatabase._init();
  static Database? _database;

  DownloadDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('downloads.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
CREATE TABLE downloaded_chapters (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  mangaId INTEGER NOT NULL,
  chapterId INTEGER NOT NULL UNIQUE,
  chapterTitle TEXT NOT NULL,
  downloadStatus INTEGER NOT NULL,
  pageCount INTEGER NOT NULL
)
''');
  }

  Future<int> insertChapter(Map<String, dynamic> chapter) async {
    final db = await instance.database;
    return await db.insert(
      'downloaded_chapters',
      chapter,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateChapterStatus(int chapterId, int status) async {
    final db = await instance.database;
    return await db.update(
      'downloaded_chapters',
      {'downloadStatus': status},
      where: 'chapterId = ?',
      whereArgs: [chapterId],
    );
  }

  Future<int> deleteChapter(int chapterId) async {
    final db = await instance.database;
    return await db.delete(
      'downloaded_chapters',
      where: 'chapterId = ?',
      whereArgs: [chapterId],
    );
  }

  Future<Map<String, dynamic>?> getChapter(int chapterId) async {
    final db = await instance.database;
    final maps = await db.query(
      'downloaded_chapters',
      columns: ['mangaId', 'chapterId', 'chapterTitle', 'downloadStatus', 'pageCount'],
      where: 'chapterId = ?',
      whereArgs: [chapterId],
    );

    if (maps.isNotEmpty) {
      return maps.first;
    } else {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getAllChapters() async {
    final db = await instance.database;
    return await db.query('downloaded_chapters');
  }
}

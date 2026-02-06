import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../database/models.dart';

class DbConnector {
  static final DbConnector instance = DbConnector._init();
  static Database? _database;

  DbConnector._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('scheduler_v2.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE notes ADD COLUMN volume REAL DEFAULT 1.0");
    }
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        date TEXT NOT NULL,
        time TEXT NOT NULL,
        has_appointment INTEGER NOT NULL,
        alarm_audio_path TEXT,
        volume REAL DEFAULT 1.0
      )
    ''');
  }

  Future<int> saveNote(Note note) async {
    final db = await instance.database;
    if (note.id == null) {
      return await db.insert('notes', note.toMap());
    } else {
      return await db.update(
        'notes',
        note.toMap(),
        where: 'id = ?',
        whereArgs: [note.id],
      );
    }
  }

  // Đổi tên hàm deleteTask -> deleteNote
  Future<void> deleteNote(int id) async {
    final db = await instance.database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  // Đổi tên hàm getAllTasks -> getAllNotes
  Future<List<Note>> getAllNotes() async {
    final db = await instance.database;
    // Sắp xếp theo thời gian
    final result = await db.query('notes', orderBy: 'time ASC');
    return result.map((json) => Note.fromMap(json)).toList();
  }

  Future<Note?> getNoteById(int id) async {
    final db = await instance.database;
    final result = await db.query('notes', where: 'id = ?', whereArgs: [id]);

    if (result.isNotEmpty) {
      return Note.fromMap(result.first);
    } else {
      return null;
    }
  }

  DateTime cleanDateTime(DateTime dt) {
    return DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute);
  }

  // --- THÊM MỚI: Kiểm tra trùng lịch vào khung giờ cụ thể ---
  Future<bool> checkConflict(DateTime newTime) async {
    final db = await instance.database;
    // Lấy chuỗi ISO của thời gian cần check
    // Lưu ý: Đảm bảo newTime đã được clean giây/mili giây về 0 nếu logic tạo note của bạn làm vậy
    String timeStr = cleanDateTime(newTime).toIso8601String();

    final result = await db.query(
      'notes',
      where: 'time = ? AND has_appointment = 1',
      whereArgs: [timeStr],
    );

    return result.isNotEmpty;
  }
}

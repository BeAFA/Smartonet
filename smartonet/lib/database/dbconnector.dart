import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class Dbconnector {
  static final Dbconnector instance = Dbconnector._init();
  static Database? _database;

  Dbconnector._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('smartonet_v2.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    // 1. Bảng Notes (Lưu trữ nội dung text)
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_date TEXT NOT NULL,
        active INTEGER NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        remind INTEGER NOT NULL, -- 1: Có nhắc nhở, 0: Không
        tag TEXT
      )
    ''');

    // 2. Bảng Reminders (Lưu trữ thời gian)
    // ON DELETE CASCADE: Xóa Note -> Tự động xóa Reminder này
    await db.execute('''
      CREATE TABLE reminders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_date TEXT NOT NULL,
        active INTEGER NOT NULL,
        note_id INTEGER NOT NULL UNIQUE, -- UNIQUE để đảm bảo 1 Note chỉ có 1 Reminder
        scheduled_time TEXT NOT NULL,
        FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
      )
    ''');
    print("📂 Database & Tables Created");
  }

  // =========================================================
  // LOGIC XỬ LÝ LIÊN KẾT & CẬP NHẬT THÔNG MINH
  // =========================================================

  /// Hàm này xử lý cả Tạo mới (Insert) và Cập nhật (Update)
  /// - id: Nếu null -> Tạo mới. Nếu có số -> Cập nhật.
  /// - scheduledTime: Nếu null -> Là Ghi chú thường. Nếu có chuỗi -> Là Nhắc nhở (Liên kết).
  Future<void> saveNoteOrReminder({
    int? id,
    required String title,
    required String content,
    String? scheduledTime, // "HH:mm dd/MM/yyyy" hoặc null
    String tag = 'General',
  }) async {
    final db = await instance.database;
    final String currentDate = DateTime.now().toString();

    // Sử dụng Transaction để đảm bảo tính toàn vẹn dữ liệu (Insert cả 2 hoặc fail cả 2)
    await db.transaction((txn) async {
      int noteId;

      // --- BƯỚC 1: XỬ LÝ BẢNG NOTES ---
      Map<String, dynamic> noteData = {
        'title': title,
        'content': content,
        'created_date': currentDate,
        'active': 1,
        'tag': tag,
        'remind': scheduledTime != null ? 1 : 0, // Đánh dấu cờ remind
      };

      if (id == null) {
        // A. Tạo mới Note
        noteId = await txn.insert('notes', noteData);
      } else {
        // B. Cập nhật Note
        noteId = id;
        await txn.update('notes', noteData, where: 'id = ?', whereArgs: [id]);
      }

      // --- BƯỚC 2: XỬ LÝ LIÊN KẾT BẢNG REMINDERS ---
      
      if (scheduledTime != null && scheduledTime.isNotEmpty) {
        // TRƯỜNG HỢP 1: Có thời gian -> Cần có liên kết (Tạo hoặc Update Reminder)
        
        // Kiểm tra xem đã có reminder cho note này chưa
        List<Map> existing = await txn.query(
          'reminders', 
          where: 'note_id = ?', 
          whereArgs: [noteId]
        );

        if (existing.isEmpty) {
          // Chưa có -> Tạo mới liên kết Reminder
          await txn.insert('reminders', {
            'created_date': currentDate,
            'active': 1,
            'note_id': noteId, // Liên kết khóa ngoại
            'scheduled_time': scheduledTime,
          });
        } else {
          // Đã có -> Cập nhật thời gian
          await txn.update(
            'reminders', 
            {'scheduled_time': scheduledTime},
            where: 'note_id = ?',
            whereArgs: [noteId]
          );
        }
      } else {
        // TRƯỜNG HỢP 2: Không có thời gian (scheduledTime == null/empty)
        // -> Đây là ghi chú độc lập.
        // -> Nếu trước đó nó là Reminder (có trong bảng reminders), ta phải XÓA liên kết đó đi.
        await txn.delete(
          'reminders', 
          where: 'note_id = ?', 
          whereArgs: [noteId]
        );
      }
    });
  }

  // =========================================================
  // LOGIC XÓA (DELETE ONE -> DELETE ALL)
  // =========================================================

  /// Chỉ cần truyền ID của Note.
  /// - Nếu nó là Note thường: Xóa Note.
  /// - Nếu nó là Note có liên kết Reminder: Xóa Note -> SQL tự động xóa Reminder (Cascade).
  Future<int> deleteItem(int noteId) async {
    final db = await instance.database;
    return await db.delete(
      'notes',
      where: 'id = ?',
      whereArgs: [noteId],
    );
  }
  
  // Hàm lấy dữ liệu (Ví dụ để test)
  Future<List<Map<String, dynamic>>> getAllData() async {
    final db = await instance.database;
    // Query Left Join để lấy cả Note và giờ nhắc (nếu có)
    return await db.rawQuery('''
      SELECT 
        notes.*, 
        reminders.scheduled_time 
      FROM notes 
      LEFT JOIN reminders ON notes.id = reminders.note_id
      ORDER BY notes.created_date DESC
    ''');
  }

  
}
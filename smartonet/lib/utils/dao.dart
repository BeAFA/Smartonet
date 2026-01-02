import '../database/dbconnector.dart';
import '../database/models.dart';

class NoteDao {
  // Hàm tạo Note kèm logic tự động tạo Reminder
  Future<void> createNote(Note note, {DateTime? scheduledTime}) async {
    // 1. Lấy kết nối từ DBConnector
    final db = await Dbconnector.instance.database;

    // 2. Dùng Transaction để đảm bảo toàn vẹn dữ liệu
    await db.transaction((txn) async {
      // Lưu Note
      final int newNoteId = await txn.insert('notes', note.toMap());
      print("✅ DAO: Đã lưu Note ID: $newNoteId");

      // Logic: Nếu remind=true VÀ có thời gian hẹn -> Tạo Reminder
      if (note.remind && scheduledTime != null) {
        final newReminder = Reminder(
          noteId: newNoteId,
          scheduledTime: scheduledTime,
        );

        await txn.insert('reminders', newReminder.toMap());
        print("🔔 DAO: Đã tạo Reminder lúc $scheduledTime");
      }
    });
  }

  Future<void> updateNoteOrReminder({
    required int id, // ID của Note
    required String title,
    required String content,
    DateTime?
    scheduledTime, // Nếu null => Xóa nhắc nhở, giữ Note. Nếu có ngày => Cập nhật giờ
  }) async {
    await Dbconnector.instance.saveNoteOrReminder(
      id: id,
      title: title,
      content: content,
      scheduledTime: scheduledTime
          ?.toString(), // Chuyển DateTime sang String ISO
    );
  }

  // 2. Hàm Xóa (Xóa Note -> Tự động xóa Reminder nhờ Cascade)
  Future<void> deleteNote(int noteId) async {
    await Dbconnector.instance.deleteItem(noteId);
  }

  // 3. Hàm lấy danh sách Reminder kèm thông tin chi tiết của Note (JOIN bảng)
  Future<List<Map<String, dynamic>>> getRemindersWithDetails() async {
    final db = await Dbconnector.instance.database;
    // JOIN bảng notes và reminders để lấy tiêu đề note gắn vào reminder
    return await db.rawQuery('''
      SELECT 
        reminders.id as reminder_id,
        reminders.scheduled_time,
        reminders.note_id,
        notes.title,
        notes.content,
        notes.tag
      FROM reminders
      INNER JOIN notes ON reminders.note_id = notes.id
      ORDER BY reminders.scheduled_time ASC
    ''');
  }

  // 4. Hàm lấy Notes và Reminders riêng biệt (dùng để test)
  Future<List<Map<String, dynamic>>> getNotes() async {
    final db = await Dbconnector.instance.database;
    return await db.query('notes', orderBy: 'created_date DESC');
  }

  Future<List<Map<String, dynamic>>> getReminders() async {
    final db = await Dbconnector.instance.database;
    return await db.query('reminders');
  }
}

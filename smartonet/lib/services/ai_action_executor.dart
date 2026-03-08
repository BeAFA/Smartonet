import 'package:flutter/foundation.dart';
import '../database/models.dart';
import 'dbconnector.dart';
import 'alarm_service.dart';

class AiActionExecutor {
  static Future<bool> execute(Map<String, dynamic> jsonMap) async {
    try {
      final action = jsonMap['action'];
      final title = jsonMap['title'] ?? 'Ghi chú AI';
      final content = jsonMap['content'] ?? '';
      final datetimeStr = jsonMap['datetime'];

      DateTime timeToSave = DateTime.now();
      bool hasAppt = false;

      // Xử lý thời gian nếu là báo thức
      if (action == 'create_alarm' && datetimeStr != null) {
        timeToSave = DateTime.parse(datetimeStr);
        hasAppt = true;
      }

      // Tạo đối tượng Note
      Note noteToSave = Note(
        title: title,
        content: content,
        date: DateTime(timeToSave.year, timeToSave.month, timeToSave.day),
        time: timeToSave,
        hasAppointment: hasAppt,
        volume: 1.0,
      );

      // Lưu DB
      int id = await DbConnector.instance.saveNote(noteToSave);
      noteToSave.id = id;

      // Đặt báo thức nếu cần
      if (hasAppt && timeToSave.isAfter(DateTime.now())) {
        await AppointmentService.scheduleAppointment(noteToSave);
      }

      return true;
    } catch (e) {
      debugPrint('Lỗi khi thực thi hành động AI: $e');
      return false;
    }
  }
}

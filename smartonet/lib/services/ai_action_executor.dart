import 'package:flutter/foundation.dart';
import '../database/models.dart';
import 'dbconnector.dart';
import 'alarm_service.dart';

class AiActionExecutor {
  // Hàm chính nhận JSON từ AI
  static Future<bool> execute(Map<String, dynamic> jsonMap) async {
    try {
      // Trích xuất mảng các lệnh
      final List<dynamic> commands = jsonMap['commands'] ?? [];

      // Nếu không có mảng commands (ví dụ AI trả về format cũ hoặc rỗng), thử xử lý nguyên gốc
      if (commands.isEmpty) {
        return await _executeSingleCommand(jsonMap);
      }

      bool allSuccess = true;
      
      // Duyệt qua từng lệnh trong mảng và thực thi
      for (var cmd in commands) {
        if (cmd is Map<String, dynamic>) {
          bool success = await _executeSingleCommand(cmd);
          if (!success) allSuccess = false; // Nếu có 1 lệnh lỗi thì đánh dấu là false
        }
      }

      return allSuccess;
    } catch (e) {
      debugPrint('Lỗi khi thực thi danh sách hành động AI: $e');
      return false;
    }
  }

  // Hàm phụ xử lý từng lệnh một (Đây chính là logic cũ của bạn)
  static Future<bool> _executeSingleCommand(Map<String, dynamic> cmdMap) async {
    try {
      final String? action = cmdMap['action'];
      if (action == null) return false;

      final int? targetId = cmdMap['target_id'] != null ? (cmdMap['target_id'] as num).toInt() : null;
      final bool hasAppt = cmdMap['has_appointment'] ?? false;
      
      final title = cmdMap['title'] ?? 'Ghi chú AI';
      final content = cmdMap['content'] ?? '';
      final datetimeStr = cmdMap['datetime'];
      final volume = (cmdMap['volume'] ?? 0).toDouble();

      // --- 1. XÓA (DELETE) ---
      if (action == 'delete') {
        if (targetId == null) return false;
        await AppointmentService.cancelAlarm(targetId);
        await DbConnector.instance.deleteNote(targetId);
        return true;
      }

      // --- 2. TẠO MỚI (CREATE) ---
      if (action == 'create') {
        DateTime timeToSave = datetimeStr != null ? DateTime.parse(datetimeStr) : DateTime.now();

        Note noteToSave = Note(
          title: title,
          content: content,
          date: DateTime(timeToSave.year, timeToSave.month, timeToSave.day),
          time: timeToSave,
          hasAppointment: hasAppt,
          volume: volume,
        );

        int id = await DbConnector.instance.saveNote(noteToSave);
        noteToSave.id = id;

        if (hasAppt && timeToSave.isAfter(DateTime.now())) {
          await AppointmentService.scheduleAppointment(noteToSave);
        }
        return true;
      }

      // --- 3. CẬP NHẬT (UPDATE) ---
      if (action == 'update') {
        if (targetId == null) return false;
        
        Note? oldNote = await DbConnector.instance.getNoteById(targetId);
        if (oldNote == null) return false;

        await AppointmentService.cancelAlarm(targetId);

        DateTime newTime = datetimeStr != null ? DateTime.parse(datetimeStr) : oldNote.time;
        
        Note updatedNote = Note(
          id: oldNote.id,
          title: cmdMap['title'] ?? oldNote.title,
          content: cmdMap['content'] ?? oldNote.content,
          date: DateTime(newTime.year, newTime.month, newTime.day),
          time: newTime,
          hasAppointment: hasAppt, 
          volume: volume > 0 ? volume : oldNote.volume,
          alarmAudioPath: oldNote.alarmAudioPath,
        );

        await DbConnector.instance.saveNote(updatedNote);

        if (updatedNote.hasAppointment && updatedNote.time.isAfter(DateTime.now())) {
          await AppointmentService.scheduleAppointment(updatedNote);
        }
        return true;
      }

      return false; 
    } catch (e) {
      debugPrint('Lỗi khi thực thi lệnh đơn lẻ: $e');
      return false;
    }
  }
}
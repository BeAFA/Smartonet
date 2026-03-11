import 'package:flutter/material.dart';
import '../database/models.dart';
import 'dbconnector.dart';
import 'alarm_service.dart';
import 'audio_service.dart';
import '../screens/audio_preview_screen.dart';

// =========================================================================
// 1. ĐỊNH NGHĨA KIỂU HÀM XỬ LÝ
// =========================================================================
typedef CommandHandler = Future<bool> Function(Map<String, dynamic> payload);

// =========================================================================
// 2. ENUM ĐĂNG KÝ CHỨC NĂNG (REGISTRY PATTERN)
// =========================================================================
enum AppCommand {
  // --- Các lệnh liên quan đến Ghi chú & Lịch hẹn ---
  createNote('create', _handleCreateNote),
  updateNote('update', _handleUpdateNote),
  deleteNote('delete', _handleDeleteNote),

  // --- Các lệnh liên quan đến Báo thức & Âm thanh ---
  previewAudio('preview_audio', _handlePreviewAudio),
  stopPreview('stop_preview', _handleStopPreview),
  deleteAudio('delete_audio', _handleDeleteAudio);

  final String keyword;
  final CommandHandler handler;

  const AppCommand(this.keyword, this.handler);

  // Tra cứu Enum từ keyword do AI gửi về
  static AppCommand? fromKeyword(String keyword) {
    for (var command in AppCommand.values) {
      if (command.keyword == keyword) return command;
    }
    return null;
  }
}

// =========================================================================
// 3. BỘ PHÂN PHỐI LỆNH TRUNG TÂM (DISPATCHER)
// =========================================================================
class AiActionExecutor {
  static Future<bool> execute(
    Map<String, dynamic> jsonMap, {
    BuildContext? context,
  }) async {
    try {
      final List<dynamic> commands = jsonMap['commands'] ?? [];

      // Xử lý fallback nếu AI không trả về mảng commands
      if (commands.isEmpty) {
        return await _dispatchCommand(jsonMap, context);
      }

      bool allSuccess = true;
      for (var cmd in commands) {
        if (cmd is Map<String, dynamic>) {
          bool success = await _dispatchCommand(cmd, context);
          if (!success) allSuccess = false;
        }
      }
      return allSuccess;
    } catch (e) {
      debugPrint('Lỗi khi thực thi danh sách hành động AI: $e');
      return false;
    }
  }

  static Future<bool> _dispatchCommand(
    Map<String, dynamic> cmdMap,
    BuildContext? context,
  ) async {
    final String? actionKeyword = cmdMap['action'];
    if (actionKeyword == null) return false;

    // Tìm lệnh đã đăng ký
    final command = AppCommand.fromKeyword(actionKeyword);

    if (command == null) {
      debugPrint('AI gửi lệnh không được hỗ trợ: $actionKeyword');
      return false;
    }

    if (actionKeyword == 'preview_audio') {
      if (context != null && context.mounted) {
        // Lấy dữ liệu từ AI
        final String keyword = cmdMap['keyword'] ?? 'all';
        final String audioType = cmdMap['audio_type'] ?? 'both';
        final int playCount = cmdMap['play_count'] ?? 1;
        final int? duration = cmdMap['duration_in_seconds'];

        // Mở màn hình AudioPreviewScreen thay vì gọi ngầm
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AudioPreviewScreen(
              keyword: keyword,
              targetType: audioType,
              playCount: playCount,
              durationInSeconds: duration,
            ),
          ),
        );
        return true;
      } else {
        debugPrint("Thiếu BuildContext, không thể mở màn hình phát nhạc!");
        return false;
      }
    }

    // Các lệnh khác (create, update, delete...) vẫn chạy như bình thường
    return await command.handler(cmdMap);
  }
}

// =========================================================================
// 4. CÁC HÀM XỬ LÝ LOGIC CHI TIẾT (HANDLERS)
// =========================================================================

// ---------------- Lĩnh vực Ghi chú (Notes) ----------------

Future<bool> _handleCreateNote(Map<String, dynamic> cmdMap) async {
  final title = cmdMap['title'] ?? 'Ghi chú AI';
  final content = cmdMap['content'] ?? '';
  final datetimeStr = cmdMap['datetime'];
  final hasAppt = cmdMap['has_appointment'] ?? false;
  final volume = (cmdMap['volume'] ?? 0).toDouble();

  DateTime timeToSave = datetimeStr != null
      ? DateTime.parse(datetimeStr)
      : DateTime.now();

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

Future<bool> _handleUpdateNote(Map<String, dynamic> cmdMap) async {
  final int? targetId = cmdMap['target_id'] != null
      ? (cmdMap['target_id'] as num).toInt()
      : null;
  if (targetId == null) return false;

  Note? oldNote = await DbConnector.instance.getNoteById(targetId);
  if (oldNote == null) return false;

  await AppointmentService.cancelAlarm(targetId);

  final datetimeStr = cmdMap['datetime'];
  DateTime newTime = datetimeStr != null
      ? DateTime.parse(datetimeStr)
      : oldNote.time;
  final volume = (cmdMap['volume'] ?? 0).toDouble();
  final hasAppt = cmdMap['has_appointment'] ?? oldNote.hasAppointment;

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

Future<bool> _handleDeleteNote(Map<String, dynamic> cmdMap) async {
  final int? targetId = cmdMap['target_id'] != null
      ? (cmdMap['target_id'] as num).toInt()
      : null;
  if (targetId == null) return false;

  await AppointmentService.cancelAlarm(targetId);
  await DbConnector.instance.deleteNote(targetId);
  return true;
}

// ---------------- Lĩnh vực Âm thanh & Báo thức (Audio/Alarms) ----------------

Future<bool> _handlePreviewAudio(Map<String, dynamic> payload) async {
  final String? keyword = payload['keyword'];
  final String audioType = payload['audio_type'] ?? 'both';
  final int playCount = payload['play_count'] ?? 1;
  final int? duration = payload['duration_in_seconds'];

  // Gọi hàm phát nhạc thông minh
  await AudioService().previewAdvanced(
    keyword: keyword,
    targetType: audioType,
    playCount: playCount,
    durationInSeconds: duration,
  );
  return true;
}

Future<bool> _handleStopPreview(Map<String, dynamic> payload) async {
  await AudioService().stopPreview();
  return true;
}

Future<bool> _handleDeleteAudio(Map<String, dynamic> payload) async {
  final String? keyword = payload['keyword'];
  if (keyword != null && keyword.isNotEmpty) {
    return await AudioService().deleteCustomAudioByKeyword(keyword);
  }
  return false;
}

import 'package:flutter/material.dart';
import '../database/models.dart';
import 'dbconnector.dart';
import 'alarm_service.dart';
import 'audio_service.dart';
import '../screens/audio_preview_screen.dart';

// =========================================================================
// 1. CLASS KẾT QUẢ THỰC THI (MỚI)
// =========================================================================
class CommandResult {
  final Map<String, dynamic> command;
  final bool isSuccess;
  final String? errorMessage;

  CommandResult({
    required this.command,
    required this.isSuccess,
    this.errorMessage,
  });
}

class AiExecutionResult {
  final List<CommandResult> results;

  AiExecutionResult(this.results);

  bool get hasError => results.any((r) => !r.isSuccess);

  List<CommandResult> get successes => results.where((r) => r.isSuccess).toList();
  List<CommandResult> get failures => results.where((r) => !r.isSuccess).toList();
}

// =========================================================================
// 2. ĐỊNH NGHĨA KIỂU HÀM XỬ LÝ
// =========================================================================
typedef CommandHandler = Future<CommandResult> Function(Map<String, dynamic> payload);

// =========================================================================
// 3. ENUM ĐĂNG KÝ CHỨC NĂNG
// =========================================================================
enum AppCommand {
  createNote('create', _handleCreateNote),
  updateNote('update', _handleUpdateNote),
  deleteNote('delete', _handleDeleteNote),
  previewAudio('preview_audio', _handlePreviewAudio),
  stopPreview('stop_preview', _handleStopPreview),
  deleteAudio('delete_audio', _handleDeleteAudio);

  final String keyword;
  final CommandHandler handler;

  const AppCommand(this.keyword, this.handler);

  static AppCommand? fromKeyword(String keyword) {
    for (var command in AppCommand.values) {
      if (command.keyword == keyword) return command;
    }
    return null;
  }
}

// =========================================================================
// 4. BỘ PHÂN PHỐI LỆNH TRUNG TÂM (DISPATCHER)
// =========================================================================
class AiActionExecutor {
  static Future<AiExecutionResult> execute(
    Map<String, dynamic> jsonMap, {
    BuildContext? context,
  }) async {
    List<CommandResult> results = [];
    try {
      final List<dynamic> commands = jsonMap['commands'] ?? [];

      if (commands.isEmpty) {
        results.add(await _dispatchCommand(jsonMap, context));
        return AiExecutionResult(results);
      }

      for (var cmd in commands) {
        if (cmd is Map<String, dynamic>) {
          results.add(await _dispatchCommand(cmd, context));
        }
      }
      return AiExecutionResult(results);
    } catch (e) {
      debugPrint('Lỗi khi thực thi danh sách hành động AI: $e');
      results.add(CommandResult(
          command: jsonMap,
          isSuccess: false,
          errorMessage: 'Lỗi hệ thống không xác định: $e'));
      return AiExecutionResult(results);
    }
  }

  static Future<CommandResult> _dispatchCommand(
    Map<String, dynamic> cmdMap,
    BuildContext? context,
  ) async {
    final String? actionKeyword = cmdMap['action'];
    if (actionKeyword == null) {
      return CommandResult(
          command: cmdMap, isSuccess: false, errorMessage: 'Thiếu action keyword.');
    }

    final command = AppCommand.fromKeyword(actionKeyword);
    if (command == null) {
      return CommandResult(
          command: cmdMap,
          isSuccess: false,
          errorMessage: 'Lệnh không được hỗ trợ: $actionKeyword');
    }

    if (actionKeyword == 'preview_audio') {
      if (context != null && context.mounted) {
        final String keyword = cmdMap['keyword'] ?? 'all';
        final String audioType = cmdMap['audio_type'] ?? 'both';
        final int playCount = cmdMap['play_count'] ?? 1;
        final int? duration = cmdMap['duration_in_seconds'];

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
        return CommandResult(command: cmdMap, isSuccess: true);
      } else {
        return CommandResult(
            command: cmdMap,
            isSuccess: false,
            errorMessage: 'Thiếu ngữ cảnh UI để mở màn hình phát nhạc.');
      }
    }

    return await command.handler(cmdMap);
  }
}

// =========================================================================
// 5. CÁC HÀM XỬ LÝ LOGIC CHI TIẾT
// =========================================================================

Future<CommandResult> _handleCreateNote(Map<String, dynamic> cmdMap) async {
  try {
    final title = cmdMap['title'] ?? 'Ghi chú AI';
    final content = cmdMap['content'] ?? '';
    final datetimeStr = cmdMap['datetime'];
    final hasAppt = cmdMap['has_appointment'] ?? false;
    final volume = (cmdMap['volume'] ?? 0).toDouble();

    DateTime timeToSave =
        datetimeStr != null ? DateTime.parse(datetimeStr) : DateTime.now();

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
    return CommandResult(command: cmdMap, isSuccess: true);
  } catch (e) {
    return CommandResult(
        command: cmdMap, isSuccess: false, errorMessage: 'Lỗi tạo mới: $e');
  }
}

Future<CommandResult> _handleUpdateNote(Map<String, dynamic> cmdMap) async {
  try {
    final int? targetId = cmdMap['target_id'] != null
        ? (cmdMap['target_id'] as num).toInt()
        : null;
    if (targetId == null) {
      return CommandResult(
          command: cmdMap, isSuccess: false, errorMessage: 'Không có target_id.');
    }

    Note? oldNote = await DbConnector.instance.getNoteById(targetId);
    if (oldNote == null) {
      return CommandResult(
          command: cmdMap,
          isSuccess: false,
          errorMessage: 'Không tìm thấy ghi chú/lịch hẹn nào có ID $targetId.');
    }

    await AppointmentService.cancelAlarm(targetId);

    final datetimeStr = cmdMap['datetime'];
    DateTime newTime =
        datetimeStr != null ? DateTime.parse(datetimeStr) : oldNote.time;
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
    return CommandResult(command: cmdMap, isSuccess: true);
  } catch (e) {
    return CommandResult(
        command: cmdMap, isSuccess: false, errorMessage: 'Lỗi cập nhật: $e');
  }
}

Future<CommandResult> _handleDeleteNote(Map<String, dynamic> cmdMap) async {
  try {
    final int? targetId = cmdMap['target_id'] != null
        ? (cmdMap['target_id'] as num).toInt()
        : null;
    if (targetId == null) {
      return CommandResult(
          command: cmdMap, isSuccess: false, errorMessage: 'Không có target_id.');
    }

    Note? oldNote = await DbConnector.instance.getNoteById(targetId);
    if (oldNote == null) {
      return CommandResult(
          command: cmdMap,
          isSuccess: false,
          errorMessage: 'Không tìm thấy ID $targetId để xóa.');
    }

    await AppointmentService.cancelAlarm(targetId);
    await DbConnector.instance.deleteNote(targetId);
    return CommandResult(command: cmdMap, isSuccess: true);
  } catch (e) {
    return CommandResult(
        command: cmdMap, isSuccess: false, errorMessage: 'Lỗi khi xóa: $e');
  }
}

Future<CommandResult> _handlePreviewAudio(Map<String, dynamic> payload) async {
  try {
    final String? keyword = payload['keyword'];
    final String audioType = payload['audio_type'] ?? 'both';
    final int playCount = payload['play_count'] ?? 1;
    final int? duration = payload['duration_in_seconds'];

    await AudioService().previewAdvanced(
      keyword: keyword,
      targetType: audioType,
      playCount: playCount,
      durationInSeconds: duration,
    );
    return CommandResult(command: payload, isSuccess: true);
  } catch (e) {
    return CommandResult(
        command: payload, isSuccess: false, errorMessage: 'Lỗi phát nhạc: $e');
  }
}

Future<CommandResult> _handleStopPreview(Map<String, dynamic> payload) async {
  await AudioService().stopPreview();
  return CommandResult(command: payload, isSuccess: true);
}

Future<CommandResult> _handleDeleteAudio(Map<String, dynamic> payload) async {
  final String? keyword = payload['keyword'];
  if (keyword != null && keyword.isNotEmpty) {
    bool deleted = await AudioService().deleteCustomAudioByKeyword(keyword);
    if (deleted) {
      return CommandResult(command: payload, isSuccess: true);
    } else {
      return CommandResult(
          command: payload,
          isSuccess: false,
          errorMessage: 'Không tìm thấy bài nhạc chứa từ khóa "$keyword".');
    }
  }
  return CommandResult(
      command: payload, isSuccess: false, errorMessage: 'Thiếu từ khóa.');
}
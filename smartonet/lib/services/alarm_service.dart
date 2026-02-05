import 'dart:io';
import 'package:alarm/alarm.dart';
import 'package:logging/logging.dart';
import '../database/models.dart';
import 'audio_service.dart';

class AppointmentService {
  static final _log = Logger('AppointmentService');
  static Future<void> init() async {
    await Alarm.init();
  }

  static Future<bool> scheduleAppointment(Note note) async {
    // 1. Kiểm tra tính hợp lệ cơ bản
    if (!note.hasAppointment || note.id == null) return false;

    // 2. Tạo đối tượng DateTime chính xác
    final scheduledDateTime = DateTime(
      note.date.year,
      note.date.month,
      note.date.day,
      note.time.hour,
      note.time.minute,
    );

    // 3. Không đặt báo thức cho quá khứ
    if (scheduledDateTime.isBefore(DateTime.now())) {
      _log.info("Không thể đặt báo thức cho quá khứ: $scheduledDateTime");
      return false;
    }

    // 4. XỬ LÝ LOGIC ĐƯỜNG DẪN NHẠC (QUAN TRỌNG)
    String finalAudioPath = 'assets/Default/alarm_digital.wav'; // Mặc định

    if (note.alarmAudioPath != null && note.alarmAudioPath!.trim().isNotEmpty) {
      final customFile = File(note.alarmAudioPath!);
      // Kiểm tra xem file còn tồn tại trong điện thoại không
      if (await customFile.exists()) {
        finalAudioPath = note.alarmAudioPath!;
      } else {
        _log.warning("File nhạc tùy chọn không tồn tại, quay về mặc định.");
      }
    }

    // Delay nhẹ để đảm bảo UI/DB xử lý xong trước khi set Alarm
    await Future.delayed(const Duration(milliseconds: 100));

    // 5. Cấu hình AlarmSettings
    final alarmSettings = AlarmSettings(
      id: note.id!,
      dateTime: scheduledDateTime,
      assetAudioPath: finalAudioPath, // Thư viện tự handle asset hay file path
      loopAudio: true, // Lặp lại nhạc
      vibrate: true, // Rung
      volumeSettings: VolumeSettings.fade(
        fadeDuration: const Duration(seconds: 3), // Fade in 3 giây cho đỡ giật mình
        volumeEnforced: true // Bắt buộc âm lượng tối đa
      ),
      notificationSettings: NotificationSettings(
        title: 'Đến giờ: ${note.title}',
        body: note.content.isNotEmpty ? note.content : 'Nhấn để tắt báo thức',
        stopButton: 'Dừng',
        icon: 'mipmap/ic_launcher',
      ),
      // Quan trọng cho Android: Hiện màn hình full kể cả khi khóa máy
      androidFullScreenIntent: true,
      warningNotificationOnKill: false, 
    );

    // 6. Dừng báo thức cũ (nếu có trùng ID) trước khi đặt mới
    await Alarm.stop(note.id!);
    
    // 7. Đặt báo thức mới
    return await Alarm.set(alarmSettings: alarmSettings);
  }

  // Hàm hủy/dừng báo thức
  static Future<bool> stopAlarm(int id) async {
    try {
      // Dừng nhạc preview (nếu lỡ đang phát)
      await AudioService().stopPreview();
      
      // Dừng báo thức hệ thống
      return await Alarm.stop(id);
    } catch (e) {
      _log.severe("Lỗi khi dừng báo thức ID $id: $e");
      return false;
    }
  }

  // Hàm alias để code cũ của bạn gọi cancelAlarm vẫn chạy được
  static Future<void> cancelAlarm(int id) async {
    await stopAlarm(id);
  }
}
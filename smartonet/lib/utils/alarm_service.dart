import 'package:alarm/alarm.dart';
import '../database/models.dart';
import 'dart:async';

class AppointmentService {

  static Future<void> init() async {
    await Alarm.init();
  }

  // Đặt lịch hẹn (Schedule Appointment)
  static Future<void> scheduleAppointment(Note note) async {
    if (!note.hasAppointment || note.id == null) return;

    final scheduledDateTime = DateTime(
      note.date.year,
      note.date.month,
      note.date.day,
      note.time.hour,
      note.time.minute,
    );

    if (scheduledDateTime.isBefore(DateTime.now())) return;

    final alarmSettings = AlarmSettings(
      id: note.id!,
      dateTime: scheduledDateTime,
      assetAudioPath: 'assets/alarm_digital.wav',
      loopAudio: true,
      vibrate: true,
      warningNotificationOnKill: false,
      androidFullScreenIntent: false,
      androidStopAlarmOnTermination: false,
      volumeSettings: VolumeSettings.fixed(volumeEnforced: false),
      notificationSettings: NotificationSettings(
        title: 'Đến giờ: ${note.title}',
        body: note.content.isNotEmpty ? note.content : 'Nhấn để tắt báo thức',
        stopButton: 'Dừng',
        icon: 'mipmap/ic_launcher',
      ),
    );

    await Alarm.set(alarmSettings: alarmSettings);
  }

  static Future<void> cancelAppointment(int noteId) async {
    await Alarm.stop(noteId);
  }

  static Future<void> stopAlarm(int id) async {
    await Alarm.stop(id);
  }
}

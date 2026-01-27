import 'package:alarm/alarm.dart';
import '../database/models.dart';
import 'dart:async';
import 'dart:io';

class AppointmentService {
  static Future<void> init() async {
    await Alarm.init();
  }

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

    String audioPath = 'assets/Default/alarm_digital.wav';

    if (note.alarmAudioPath != null && note.alarmAudioPath!.isNotEmpty) {
      final bool fileExists = await File(note.alarmAudioPath!).exists();
      if (fileExists) {
        audioPath = note.alarmAudioPath!;
      }
    }
    final alarmSettings = AlarmSettings(
      id: note.id!,
      dateTime: scheduledDateTime,
      assetAudioPath: audioPath,
      loopAudio: true,
      vibrate: true,
      warningNotificationOnKill: true,
      androidFullScreenIntent: true,
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

  static Future<void> cancelAlarm(int id) async {
    await Alarm.stop(id);
  }
}

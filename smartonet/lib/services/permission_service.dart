import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class PermissionService {
  Future<PermissionStatus> requestNotification() async {
    return await Permission.notification.request();
  }

  Future<bool> isNotificationGranted() async {
    return await Permission.notification.isGranted;
  }

  Future<PermissionStatus> requestExactAlarm() async {
    if (!Platform.isAndroid) return PermissionStatus.granted;
    return await Permission.scheduleExactAlarm.request();
  }

  Future<bool> isAlarmGranted() async {
    if (!Platform.isAndroid) return true;
    return await Permission.scheduleExactAlarm.isGranted;
  }

  Future<Map<String, bool>> checkAllPermissions() async {
    final notif = await isNotificationGranted();
    final alarm = await isAlarmGranted();
    return {
      'notification': notif,
      'alarm': alarm,
    };
  }

  Future<Permission> checkMusicPermission() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        return Permission.audio;
      }
      return Permission.storage;
    }
    return Permission.mediaLibrary;
  }

  Future<bool> checkMusicStoragePermission() async {
    final permission = await checkMusicPermission();
    var status = await permission.status;
    if (status.isDenied) {
      status = await permission.request();
    }
    if (await permission.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }
    return status.isGranted;
  }
}

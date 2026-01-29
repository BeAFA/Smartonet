import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  /// Kiểm tra trạng thái của tất cả các quyền cần thiết
  /// Trả về Map chứa trạng thái (true = đã cấp, false = chưa cấp)
  Future<Map<String, bool>> checkAllPermissionsStatus() async {
    final notifStatus = await Permission.notification.status;
    
    PermissionStatus alarmStatus = PermissionStatus.granted;
    if (Platform.isAndroid) {
      alarmStatus = await Permission.scheduleExactAlarm.status;
    }

    final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
    final systemAlertStatus = await Permission.systemAlertWindow.status;

    return {
      'notification': notifStatus.isGranted,
      'alarm': alarmStatus.isGranted,
      'battery': batteryStatus.isGranted,
      'systemAlert': systemAlertStatus.isGranted,
    };
  }

  /// Yêu cầu quyền thông báo
  Future<bool> requestNotification() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Yêu cầu quyền lịch/báo thức chính xác (Android 12+)
  Future<bool> requestExactAlarm() async {
    if (Platform.isAndroid) {
      final status = await Permission.scheduleExactAlarm.request();
      return status.isGranted;
    }
    return true;
  }

  /// Yêu cầu quyền tối ưu pin (Chạy ngầm)
  Future<bool> requestBatteryOptimization() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    return status.isGranted;
  }

  /// Yêu cầu quyền hiển thị cửa sổ (Overlay)
  Future<bool> requestSystemAlertWindow() async {
    final status = await Permission.systemAlertWindow.request();
    return status.isGranted;
  }

  /// Mở cài đặt ứng dụng
  Future<void> openSettings() async {
    await openAppSettings();
  }

  /// Kiểm tra quyền truy cập file nhạc (Dùng cho AudioService)
  Future<bool> hasMusicStoragePermission() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        return await Permission.audio.isGranted;
      } else {
        return await Permission.storage.isGranted;
      }
    }
    return await Permission.storage.isGranted || await Permission.mediaLibrary.isGranted;
  }

  /// Yêu cầu quyền truy cập file nhạc
  Future<bool> requestMusicStoragePermission() async {
    Permission permission;
    
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        permission = Permission.audio;
      } else {
        permission = Permission.storage;
      }
    } else {
        permission = Permission.storage;
    }

    final status = await permission.request();
    
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }

    return status.isGranted;
  }
}
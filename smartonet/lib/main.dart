import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'services/alarm_service.dart';
import 'services/audio_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await AudioService().init();
  await AppointmentService.init();
  await _initAppFolders();

  final prefs = await SharedPreferences.getInstance();
  final bool seenOnboarding = prefs.getBool('seen_onboarding') ?? false;
  runApp(Smartonet(showOnboarding: !seenOnboarding));
}

Future<void> _initAppFolders() async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final customSoundsPath = p.join(directory.path, 'Sounds', 'Customize');
    final dir = Directory(customSoundsPath);

    if (!await dir.exists()) {
      await dir.create(recursive: true);
      debugPrint("Đã tạo sẵn thư mục chứa nhạc cá nhân: $customSoundsPath");
    }
  } catch (e) {
    debugPrint("Lỗi khi tạo thư mục: $e");
  }
}

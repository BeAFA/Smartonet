import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'services/alarm_service.dart';
import 'services/audio_service.dart';
import 'screens/home_screen.dart';
import 'screens/permission_screen.dart';
import 'dart:async';
import 'utils/notification.dart';


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

class Smartonet extends StatelessWidget {
  final bool showOnboarding;
  const Smartonet({super.key, required this.showOnboarding});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smartonet',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      ),
      scaffoldMessengerKey: messengerKey,
      home: showOnboarding ? const PermissionScreen() : const MainScreen(),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  final prefs = await SharedPreferences.getInstance();
  final bool seenOnboarding = prefs.getBool('seen_onboarding') ?? false;
  runApp(Smartonet(showOnboarding: !seenOnboarding));
}
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../utils/permission_service.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen>
    with WidgetsBindingObserver {
  bool _isNotificationGranted = false;
  bool _isAlarmGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  // Sử dụng service để kiểm tra
  Future<void> _checkPermissions() async {
    final statusMap = await PermissionService().checkAllPermissionsStatus();

    setState(() {
      _isNotificationGranted = statusMap['notification'] ?? false;
      _isAlarmGranted = statusMap['alarm'] ?? false;
    });
  }

  // Sử dụng service để request
  Future<void> _requestNotification() async {
    await PermissionService().requestNotification();
    _checkPermissions();
  }

  Future<void> _requestAlarm() async {
    await PermissionService().requestExactAlarm();
    _checkPermissions();
  }

  Future<void> _openAppSettings() async {
    await PermissionService().openSettings();
  }

  bool get _allPermissionsGranted => _isNotificationGranted && _isAlarmGranted;

  Future<void> _finishOnboarding() async {
    if (_allPermissionsGranted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('seen_onboarding', true);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Bạn chưa cấp đủ quyền để ứng dụng hoạt động chính xác",
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Cấp quyền cần thiết"),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                children: [
                  const Text(
                    "Để Smartonet hoạt động chính xác trên mọi thiết bị (đặc biệt là Xiaomi, Oppo...), vui lòng cấp đủ các quyền sau:",
                    style: TextStyle(fontSize: 16, color: Colors.black87),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: const [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.deepOrange,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Dành cho máy Xiaomi, Oppo, Vivo...",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.deepOrange,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Vui lòng nhấn nút bên dưới, tìm ứng dụng Smartonet và bật:\n"
                    "• Tự khởi chạy (Autostart)\n"
                    "• Hiển thị trên màn hình khóa\n"
                    "• Hiển thị cửa sổ Pop-up",
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _openAppSettings,
                    child: const Text("Mở Cài đặt Ứng dụng"),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              "Những quyền cơ bản:",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 10),
            // 1. Quyền Thông báo
            _buildPermissionItem(
              title: "Thông báo",
              description: "Để hiển thị thông báo khi đến giờ hẹn.",
              icon: Icons.notifications_active,
              isGranted: _isNotificationGranted,
              onPressed: _requestNotification,
            ),

            // 2. Quyền Báo thức chính xác
            if (Platform.isAndroid)
              _buildPermissionItem(
                title: "Lịch & Báo thức",
                description: "Cho phép đặt lịch hẹn chính xác từng phút.",
                icon: Icons.access_alarm,
                isGranted: _isAlarmGranted,
                onPressed: _requestAlarm,
              ),

            const Divider(height: 30),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _finishOnboarding,
                child: const Text("Đã xong, Vào ứng dụng"),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionItem({
    required String title,
    required String description,
    required IconData icon,
    required bool isGranted,
    required VoidCallback onPressed,
  }) {
    return Card(
      elevation: 0,
      color: isGranted ? Colors.green.shade50 : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isGranted ? Colors.transparent : Colors.grey.shade300,
        ),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isGranted ? Colors.green.shade100 : Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isGranted ? Icons.check : icon,
                color: isGranted ? Colors.green : Colors.blue,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            if (!isGranted)
              TextButton(onPressed: onPressed, child: const Text("Cấp")),
          ],
        ),
      ),
    );
  }
}

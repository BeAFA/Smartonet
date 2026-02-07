import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartonet/utils/notification.dart';
import '../services/permission_service.dart';
import './home_screen.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen>
    with WidgetsBindingObserver {
  bool _isNotificationGranted = false;
  bool _isAlarmGranted = false;
  bool _checkBannerVisible = false;
  bool _askedNotificationSecondTime = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkPermissions();
      if (!_isNotificationGranted) {
        await PermissionService().requestNotification();
        await _checkPermissions();
      }
    });
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

  Future<void> _checkPermissions() async {
    final statuses = await PermissionService().checkAllPermissions();
    if (!mounted) return;
    setState(() {
      _isNotificationGranted = statuses['notification'] ?? false;
      _isAlarmGranted = statuses['alarm'] ?? false;
    });
  }

  Future<void> _finishOnboarding() async {
    await _checkPermissions();
    if (_isAlarmGranted) {
      if (!_isNotificationGranted && !_askedNotificationSecondTime) {
        _askedNotificationSecondTime = true;
        await PermissionService().requestNotification();
        await _checkPermissions();
        if (!_isNotificationGranted) return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('seen_onboarding', true);
      messengerKey.currentState?.hideCurrentMaterialBanner();
      _checkBannerVisible = false;
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
    } else {
      if (!_checkBannerVisible) {
        _checkBannerVisible = true;
        showPermissionBanner(
          onDismiss: () {
            _checkBannerVisible = false;
          },
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Thiết lập cần thiết"),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text(
              "Để ứng dụng hoạt động chính xác, vui lòng cấp các quyền sau:",
              style: TextStyle(fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton.icon(
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith<Color>((
                    states,
                  ) {
                    if (_isNotificationGranted) return Colors.green;
                    return Colors.deepOrange;
                  }),
                  foregroundColor: WidgetStateProperty.all(Colors.white),
                ),
                icon: Icon(
                  _isNotificationGranted
                      ? Icons.check_circle
                      : Icons.notifications_active,
                  size: 26,
                ),
                label: Text(
                  _isNotificationGranted
                      ? "Đã cấp quyền thông báo"
                      : "Cấp quyền thông báo",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                onPressed: _isNotificationGranted
                    ? null
                    : () async {
                      _askedNotificationSecondTime = true;
                        PermissionStatus granted = await PermissionService()
                            .requestNotification();
                        if (granted.isPermanentlyDenied) {
                          if (!context.mounted) return;
                          showPermissionDialog(context);
                        }
                      },
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton.icon(
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith<Color>((
                    states,
                  ) {
                    if (_isAlarmGranted) return Colors.green;
                    return Colors.deepOrange;
                  }),
                  foregroundColor: WidgetStateProperty.all(Colors.white),
                ),
                icon: Icon(
                  _isAlarmGranted ? Icons.check_circle : Icons.alarm,
                  size: 26,
                ),
                label: Text(
                  _isAlarmGranted
                      ? "Đã cấp quyền báo thức"
                      : "Cấp quyền báo thức",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                onPressed: _isAlarmGranted
                    ? null
                    : () async {
                        final status = await PermissionService()
                            .requestExactAlarm();
                        if (status.isPermanentlyDenied || status.isDenied) {
                          if (!context.mounted) return;
                          showPermissionBanner(
                            onDismiss: () {
                              _checkBannerVisible = false;
                            },
                          );
                        }
                        await _checkPermissions();
                      },
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orange.shade50, Colors.orange.shade100],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.orange.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.deepOrange.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.deepOrange,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "Quan trọng với Xiaomi, Oppo, Vivo…",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.deepOrange,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Các hãng này có chế độ tiết kiệm pin mạnh có thể tắt ứng dụng khi chạy nền. "
                    "Hãy bật thêm các mục sau trong phần Cài đặt ứng dụng:",
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  _bullet("Cho phép tự động khởi chạy"),
                  _bullet("Cho phép hiển thị trên màn hình khóa"),
                  _bullet("Cho phép chạy dưới nền"),
                  _bullet("Bật tối ưu hóa pin cho ứng dụng"),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.settings),
                      label: const Text(
                        "Mở Cài đặt Ứng dụng",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () async {
                        await openAppSettings();
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton(
            onPressed: _finishOnboarding,
            child: const Text(
              "Đã xong, Vào ứng dụng",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("• ", style: TextStyle(fontSize: 14)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

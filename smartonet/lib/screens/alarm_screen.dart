import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import '../database/models.dart';
import '../utils/alarm_service.dart';
import '../utils/dbconnector.dart';
import '../main.dart';
import 'dart:async';

class AlarmScreen extends StatefulWidget {
  final AlarmSettings alarmSettings;

  const AlarmScreen({super.key, required this.alarmSettings});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen>
    with SingleTickerProviderStateMixin {
  Note? _currentNote;
  bool _isLoading = true;

  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    // Load dữ liệu ghi chú ngay khi vào màn hình
    _loadNoteData();

    // Hiệu ứng rung chuông (Animation)
    _controller = AnimationController(
      duration: const Duration(seconds: 1), // Nhanh hơn chút cho khẩn trương
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadNoteData() async {
    try {
      final note = await DbConnector.instance.getNoteById(
        widget.alarmSettings.id,
      );
      if (mounted) {
        setState(() {
          _currentNote = note;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải dữ liệu ghi chú: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // LOGIC DỪNG BÁO THỨC (QUAN TRỌNG)
  Future<void> _handleStop() async {
    setState(() => _isLoading = true);
    
    // Gọi hàm dừng tập trung ở AppointmentService
    await AppointmentService.stopAlarm(widget.alarmSettings.id);

    if (mounted) {
      // Thoát về màn hình chính và xóa lịch sử navigation để không back lại được màn hình này
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const MainScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  // LOGIC HOÃN BÁO THỨC (SNOOZE)
  Future<void> _handleSnooze() async {
    // 1. Dừng âm thanh báo thức hiện tại trước
    await AppointmentService.stopAlarm(widget.alarmSettings.id);

    // Nếu không tìm thấy ghi chú gốc, chỉ dừng và thoát
    if (_currentNote == null) {
      if (mounted) {
         Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const MainScreen()),
          (Route<dynamic> route) => false,
        );
      }
      return;
    }

    // 2. Tính toán thời gian mới (+5 phút)
    DateTime now = DateTime.now();
    DateTime newTime = now.add(const Duration(minutes: 5));

    // 3. (Tùy chọn) Kiểm tra xung đột nếu cần - Ở đây mình bỏ qua để ưu tiên Snooze chạy được ngay
    
    setState(() => _isLoading = true);

    try {
      // 4. Cập nhật thời gian vào Object Note
      _currentNote!.time = newTime;
      _currentNote!.date = newTime;
      _currentNote!.hasAppointment = true;

      // 5. Lưu vào Database
      await DbConnector.instance.saveNote(_currentNote!);

      // 6. Đặt lịch báo thức mới
      await AppointmentService.scheduleAppointment(_currentNote!);
      
      debugPrint("Đã hoãn báo thức 5 phút: ${newTime.toString()}");

    } catch (e) {
      debugPrint("Lỗi khi lưu snooze: $e");
    }

    // 7. Thoát màn hình
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const MainScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Dùng WillPopScope (hoặc PopScope trên Flutter mới) để chặn nút Back cứng
      body: PopScope(
        canPop: false, // Không cho phép vuốt back hoặc bấm nút back
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF2563EB), Color(0xFF1E40AF)],
            ),
          ),
          child: SafeArea(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // --- PHẦN TEXT THÔNG TIN ---
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            const Text(
                              "LỊCH HẸN",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                                letterSpacing: 4,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _currentNote?.title ?? "Báo thức",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                height: 1.2,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 16),
                            if (_currentNote?.content.isNotEmpty == true)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _currentNote!.content,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                    height: 1.4,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),

                      // --- ICON ĐỒNG HỒ ---
                      ScaleTransition(
                        scale: _scaleAnimation,
                        child: Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.2),
                            border: Border.all(color: Colors.white30, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.shade900.withOpacity(0.4),
                                blurRadius: 40,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.access_time_filled_rounded,
                            size: 80,
                            color: Colors.white,
                          ),
                        ),
                      ),

                      // --- BUTTONS ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildActionButton(
                            label: "Dừng",
                            icon: Icons.stop_rounded,
                            bgColor: const Color(0xFFEF4444),
                            iconColor: Colors.white,
                            onTap: _handleStop,
                          ),
                          const SizedBox(width: 40),
                          _buildActionButton(
                            label: "+5 Phút",
                            icon: Icons.snooze_rounded,
                            bgColor: Colors.white,
                            iconColor: const Color(0xFF2563EB),
                            onTap: _handleSnooze,
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color bgColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(30),
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(icon, color: iconColor, size: 36),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
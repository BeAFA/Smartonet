import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import '../database/models.dart';
import '../utils/alarm_service.dart';
import '../utils/dbconnector.dart';
import 'dart:async';

class AlarmScreen extends StatefulWidget {
  final AlarmSettings alarmSettings;

  const AlarmScreen({super.key, required this.alarmSettings});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

// Thêm SingleTickerProviderStateMixin để dùng Animation
class _AlarmScreenState extends State<AlarmScreen>
    with SingleTickerProviderStateMixin {
  Note? _currentNote;
  bool _isLoading = true;

  // --- THÊM CHO ANIMATION ---
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _loadNoteData();

    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  // ---------------------------

  Future<void> _loadNoteData() async {
    final note = await DbConnector.instance.getNoteById(
      widget.alarmSettings.id,
    );
    setState(() {
      _currentNote = note;
      _isLoading = false;
    });
  }

  Future<void> _handleStop() async {
    await AppointmentService.stopAlarm(widget.alarmSettings.id);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _handleSnooze() async {
    if (_currentNote == null) return;

    DateTime now = DateTime.now();
    DateTime newTime = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(minutes: 5));

    bool isConflict = await DbConnector.instance.checkConflict(newTime);

    if (isConflict) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Không thể hoãn"),
          content: Text(
            "Đã có một lịch hẹn khác vào lúc ${newTime.hour}:${newTime.minute.toString().padLeft(2, '0')}.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Đóng"),
            ),
          ],
        ),
      );
      return;
    }

    await AppointmentService.stopAlarm(widget.alarmSettings.id);

    setState(() {
      _currentNote!.time = newTime;
      _currentNote!.date = newTime;
      _currentNote!.hasAppointment = true;
    });

    await DbConnector.instance.saveNote(_currentNote!);
    await AppointmentService.scheduleAppointment(_currentNote!);

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dùng gradient cho nền trông hiện đại hơn
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2563EB),
              Color(0xFF1E40AF),
            ], // Xanh đậm dần xuống dưới
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
                    Column(
                      children: [
                        const Text(
                          "LỊCH HẸN",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 18,
                            letterSpacing: 3,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 15),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            _currentNote?.title ?? "Lịch hẹn",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_currentNote?.content.isNotEmpty == true)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                            child: Text(
                              _currentNote!.content,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 18,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),

                    // --- ICON ĐỒNG HỒ MỚI VỚI HIỆU ỨNG ---
                    ScaleTransition(
                      scale: _scaleAnimation,
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white,
                              blurRadius: 30,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.access_alarm_rounded,
                          size: 90,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                    ),

                    // ------------------------------------
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildButton(
                          label: "Dừng",
                          icon: Icons.stop_rounded,
                          color: const Color(0xFFEF4444), // Đỏ tươi hơn
                          onPressed: _handleStop,
                        ),
                        const SizedBox(width: 40),
                        _buildButton(
                          label: "+5 Phút",
                          icon: Icons.snooze_rounded,
                          color: Colors.white,
                          textColor: const Color(0xFF2563EB),
                          onPressed: _handleSnooze,
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildButton({
    required String label,
    required IconData icon,
    required Color color,
    Color textColor = Colors.white,
    required VoidCallback onPressed,
  }) {
    return Column(
      children: [
        SizedBox(
          width: 80,
          height: 80,
          child: FloatingActionButton.large(
            onPressed: onPressed,
            backgroundColor: color,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ), // Bo góc mềm hơn
            child: Icon(
              icon,
              color: textColor == Colors.white
                  ? Colors.white
                  : const Color(0xFF2563EB),
              size: 38,
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
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

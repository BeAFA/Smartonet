import 'dart:async';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';
import 'package:alarm/alarm.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/dbconnector.dart';
import '../database/models.dart';
import '../services/alarm_service.dart';
import '../screens/alarm_screen.dart';
import '../dialogs/voice_dialogs.dart';
import '../utils/notification.dart';
import '../services/permission_service.dart';
import '../dialogs/no_internet_dialog.dart';
import '../services/gemini_http_service.dart';
import '../services/ai_action_executor.dart';
import '../screens/faq_screen.dart';
import '../widgets/section_header.dart';
import '../dialogs/note_form_dialog.dart';
import '../widgets/smart_card.dart';
import '../dialogs/music_library_dialog.dart';
import '../screens/ai_chat_screen.dart';

class MainScreen extends StatefulWidget {
  final bool showPermissionWarning;

  const MainScreen({super.key, this.showPermissionWarning = false});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 1;
  List<Note> _allNotes = [];
  StreamSubscription<AlarmSet>? _subscription;
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};
  String _noteFilter = "all";
  String _appointmentFilter = "upcoming";
  bool _isEWarningShowing = false;
  bool _isProcessingVoice = false;

  // List<Note> _upcomingAppointments = [];
  List<Note> _recentNotes = [];
  // List<Note> _filteredData = [];

  @override
  void initState() {
    super.initState();
    _loadDataFromDB();

    if (widget.showPermissionWarning) {
      checkAndWarnPermission();
    }

    _subscription = Alarm.ringing.listen((alarmSet) {
      if (mounted && alarmSet.alarms.isNotEmpty) {
        _navigateToAlarmScreen(alarmSet.alarms.first);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _navigateToAlarmScreen(AlarmSettings alarmSettings) async {
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (context, animation, secondaryAnimation) {
          return AlarmScreen(alarmSettings: alarmSettings);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const curve = Curves.easeOutCubic;

          final scaleTween = Tween(
            begin: 0.95,
            end: 1.0,
          ).chain(CurveTween(curve: curve));

          final fadeTween = Tween(
            begin: 0.0,
            end: 1.0,
          ).chain(CurveTween(curve: curve));

          return FadeTransition(
            opacity: animation.drive(fadeTween),
            child: ScaleTransition(
              scale: animation.drive(scaleTween),
              child: child,
            ),
          );
        },
      ),
    );

    if (result == true && mounted) {
      _loadDataFromDB();
    }
  }

  Future<void> checkAndWarnPermission() async {
    final prefs = await SharedPreferences.getInstance();
    final isHiddenForever = prefs.getBool('hide_permission_forever') ?? false;
    if (isHiddenForever) return;
    final granted = await PermissionService().isNotificationGranted();
    if (!granted && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showNotificationPermissionDialog(context, showPermanentDisable: true);
      });
    }
  }

  Future<void> _loadDataFromDB() async {
    final notes = await DbConnector.instance.getAllNotes();

    // 1. Lịch hẹn sắp tới
    final upcoming = notes
        .where((n) => n.hasAppointment && !n.isPastAppointment)
        .toList();

    upcoming.sort((a, b) => a.time.compareTo(b.time));

    // 2. Ghi chú gần đây
    final recent = notes.toList();
    recent.sort((a, b) => b.time.compareTo(a.time));

    setState(() {
      _allNotes = notes;

      // chỉ lấy 3 lịch hẹn gần nhất
      // _upcomingAppointments = upcoming.take(3).toList();

      // lưu toàn bộ ghi chú đã sort
      _recentNotes = recent;

      // cập nhật list đang hiển thị
      _updateFilteredList();
    });
  }

  Future<void> _handleDelete(int id) async {
    bool confirm =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Xác nhận xóa"),
            content: const Text(
              "Mục này sẽ bị xóa khỏi cả Lịch hẹn và Ghi chú. Bạn chắc chứ?",
            ),
            actions: [
              TextButton(
                child: const Text("Hủy"),
                onPressed: () => Navigator.pop(ctx, false),
              ),
              TextButton(
                child: const Text("Xóa", style: TextStyle(color: Colors.red)),
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      await AppointmentService.cancelAlarm(id);
      await DbConnector.instance.deleteNote(id);
      _loadDataFromDB();
    }
  }

  void _toggleSelectAll(List data) {
    setState(() {
      if (_selectedIds.length == data.length) {
        _selectedIds.clear(); // Bỏ chọn tất cả
      } else {
        _selectedIds.clear();
        for (var n in data) {
          _selectedIds.add(n.id);
        }
      }
    });
  }

  void _openNoteForm(BuildContext context, {Note? existingNote}) {
    showDialog(
      context: context,
      builder: (context) {
        return NoteFormDialog(
          noteData: existingNote,
          onSubmit: (title, content, pickedDate, pickedTime, audioPath, volume) async {
            final bool hasAppt = pickedTime != null;

            DateTime finalTime;
            final DateTime now = DateTime.now();

            if (hasAppt) {
              // --- TRƯỜNG HỢP: LỊCH HẸN ---
              // Chắc chắn pickedDate không null nếu pickedTime không null (do logic validate trong Dialog)
              // Nhưng để an toàn ta dùng "pickedDate ?? now"
              DateTime baseDate = pickedDate ?? now;

              finalTime = DateTime(
                baseDate.year,
                baseDate.month,
                baseDate.day,
                pickedTime.hour,
                pickedTime.minute,
              );

              // Kiểm tra trùng giờ...
              if (finalTime.isAfter(now)) {
                final conflict = await AppointmentService.isTimeConflict(
                  finalTime,
                  ignoreNoteId: existingNote?.id,
                );

                if (conflict) {
                  if (context.mounted) await showConflictDialog(context);
                  return;
                }
              }
            } else {
              // --- TRƯỜNG HỢP: NOTE THƯỜNG (Không báo thức) ---

              if (pickedDate != null) {
                // A. Người dùng CÓ chọn ngày mới trong form -> Dùng ngày đó
                // Giữ giờ hiện tại để sort cho hợp lý, hoặc dùng 00:00
                finalTime = DateTime(
                  pickedDate.year,
                  pickedDate.month,
                  pickedDate.day,
                  now.hour,
                  now.minute,
                );
              } else if (existingNote != null) {
                // B. Người dùng KHÔNG chọn ngày mới, đang sửa Note cũ -> Giữ nguyên ngày cũ
                finalTime = existingNote.time;
              } else {
                // C. Tạo mới hoàn toàn và không chọn ngày -> Dùng hôm nay
                finalTime = now;
              }
            }

            Note noteToSave = Note(
              id: existingNote?.id,
              title: title,
              content: content,
              date: DateTime(
                finalTime.year,
                finalTime.month,
                finalTime.day,
              ), // dateOnly
              time: finalTime,
              hasAppointment: hasAppt,
              alarmAudioPath: audioPath,
              volume: volume,
            );

            int id = await DbConnector.instance.saveNote(noteToSave);
            noteToSave.id = id;

            if (hasAppt && finalTime.isAfter(DateTime.now())) {
              await AppointmentService.scheduleAppointment(noteToSave);
            } else if (existingNote != null && existingNote.id != null) {
              // Nếu sửa từ "Có hẹn" thành "Không hẹn" -> Hủy alarm cũ
              await AppointmentService.cancelAlarm(existingNote.id!);
            }

            await _loadDataFromDB();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Smartonet',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.library_music_outlined),
            tooltip: 'Kho nhạc',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const MusicLibraryDialog(),
              );
            },
          ),
          PopupMenuButton<int>(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Lịch sử báo thức',
            offset: const Offset(0, 40),
            elevation: 0,
            color: Colors.transparent, // vẫn để trong suốt
            itemBuilder: (context) {
              final recent = _getRecentPastAppointments();

              return [
                PopupMenuItem<int>(
                  enabled: false,
                  padding: EdgeInsets.zero, // QUAN TRỌNG
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 350, // 👈 Giới hạn chiều cao menu
                    ),
                    child: Container(
                      width: 320,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: recent.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: Text(
                                  "Chưa có lịch hẹn đã qua",
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            )
                          : Scrollbar(
                              // 👈 thêm scroll cho đẹp
                              child: ListView(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                children: recent.map((note) {
                                  return InkWell(
                                    onTap: () {
                                      Navigator.pop(context);
                                      _openNoteForm(
                                        context,
                                        existingNote: note,
                                      );
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.grey.shade200,
                                          width: 1,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.08,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                width: 4,
                                                height: 16,
                                                decoration: BoxDecoration(
                                                  color: Colors.orange,
                                                  borderRadius:
                                                      BorderRadius.circular(2),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  note.title,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.access_time_filled,
                                                  size: 14,
                                                  color: Colors.blue,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  "${note.date.day}/${note.date.month} • ${note.time.hour}:${note.time.minute.toString().padLeft(2, '0')}",
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.blue,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (note.content.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              note.content,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                    ),
                  ),
                ),
              ];
            },
          ),

          const SizedBox(width: 8),
          PopupMenuButton<String>(
            icon: const CircleAvatar(
              backgroundColor: Color(0xFF448AFF),
              child: Icon(Icons.info_outline, color: Colors.white),
            ),
            onSelected: (value) {
              if (value == "faq") {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FaqScreen()),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: "faq",
                child: Text("Các lỗi thường gặp"),
              ),
            ],
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildAllList(
            filterOnlyNotes: true,
          ), // Tab 0: Ghi chú (Hiển thị tất cả)
          _buildDashboard(), // Tab 1: Dashboard
          _buildAllList(filterOnlyAppointments: true), // Tab 2: Lịch hẹn
        ],
      ),
      floatingActionButton: Transform.translate(
        offset: const Offset(0, 9),
        child: _buildCustomFAB(context),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: NavigationBar(
        height: 65,
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;

            if (index == 2) {
              _appointmentFilter = "all";
            }

            if (_isSelectionMode) {
              _isSelectionMode = false;
              _selectedIds.clear();
            }
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.sticky_note_2_outlined),
            selectedIcon: Icon(Icons.sticky_note_2),
            label: 'Ghi chú',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Tổng quan',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Lịch hẹn',
          ),
        ],
      ),
    );
  }

  List<Note> _getRecentPastAppointments() {
    final past =
        _allNotes.where((n) => n.hasAppointment && n.isPastAppointment).toList()
          ..sort((a, b) => b.time.compareTo(a.time));

    return past.take(10).toList();
  }

  Widget _buildCustomFAB(BuildContext context) {
    return Container(
      height: 55,
      width: 330, // Tăng chiều rộng để đủ chỗ cho 3 nút
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          // Thêm const cho tối ưu
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: Material(
        color: const Color(0xFFE8EAF6),
        borderRadius: BorderRadius.circular(30),
        clipBehavior: Clip.hardEdge,
        child: Row(
          children: [
            // Nút 1: Thủ công (Giữ nguyên logic)
            Expanded(
              child: InkWell(
                onTap: () => _openNoteForm(context),
                child: const Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.edit, color: Color(0xFF3F51B5), size: 18),
                      SizedBox(width: 4),
                      Text(
                        "Thủ công",
                        style: TextStyle(
                          color: Color(0xFF3F51B5),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            Container(width: 1, height: 30, color: Colors.grey.shade400),

            // Nút 2: Chat AI (Mới)
            Expanded(
              child: InkWell(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AiChatScreen()),
                  );
                  _loadDataFromDB();
                },
                child: const Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        color: Colors.teal,
                        size: 18,
                      ),
                      SizedBox(width: 4),
                      Text(
                        "Chat",
                        style: TextStyle(
                          color: Colors.teal,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            Container(width: 1, height: 30, color: Colors.grey.shade400),

            // Nút 3: Giọng nói (Giữ nguyên logic)
            Expanded(
              child: InkWell(
                onTap: () {
                  showVoiceRecordDialog(context);
                },
                child: const Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.mic, color: Colors.redAccent, size: 18),
                      SizedBox(width: 4),
                      Text(
                        "Giọng nói",
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> showVoiceRecordDialog(BuildContext context) async {
    if (_isProcessingVoice) return;
    _isProcessingVoice = true;

    try {
      // 1. Kiểm tra kết nối mạng
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        if (_isEWarningShowing) return;
        _isEWarningShowing = true;
        if (context.mounted) {
          await showNoInternetDialog(context);
        }
        _isEWarningShowing = false;
        return;
      }

      if (!context.mounted) return;

      // 2. Mở hộp thoại ghi âm giọng nói
      final result = await showDialog<String>(
        context: context,
        builder: (context) {
          return const VoiceRecordDialog();
        },
      );

      if (result != null) {
        debugPrint("Text từ voice: $result");
      }

      // 3. Nếu người dùng có nói và bấm xác nhận
      if (result != null && result.isNotEmpty) {
        if (!context.mounted) return;

        // Hiện loading mờ (Vòng quay chờ AI)
        showDialog(
          context: context,
          barrierDismissible: false, // Không cho bấm ra ngoài để tắt
          builder: (ctx) => const Center(child: CircularProgressIndicator()),
        );

        // Bọc Try-Catch riêng cho phần gọi API để chống kẹt Loading
        try {
          final allData = await DbConnector.instance.getAllNotes();

          final aiResultMap = await GeminiHttpService.analyzeIntent(
            result,
            currentData: allData,
          );

          // TẮT LOADING NGAY LẬP TỨC khi có phản hồi (hoặc null)
          if (context.mounted) {
            Navigator.pop(context);
          }

          // 4. Xử lý Action và cập nhật UI
if (aiResultMap != null && context.mounted) {
  final String type = aiResultMap['type'] ?? 'conversation';
  final String aiMessage = aiResultMap['message'] ?? 'Tôi đã hiểu.';

  if (type == 'command') {
    // CHỈ THỰC THI NẾU LÀ LỆNH
    AiExecutionResult execResult = await AiActionExecutor.execute(aiResultMap, context: context);

    if (!execResult.hasError && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(aiMessage)));
      await _loadDataFromDB();
    } else if(context.mounted) {
      // LUỒNG TỰ SỬA LỖI (Dành cho lỗi kỹ thuật như sai ID)
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đang tự động xử lý lại...')));
      
      final correctionMap = await GeminiHttpService.agentSelfCorrection(
        userText: result,
        executionResult: execResult,
        currentData: allData,
      );

      if (correctionMap != null && context.mounted) {
        // Xử lý kết quả sửa lỗi tương tự như trên...
      }
    }
  } else {
    // NẾU LÀ CONVERSATION (AI đang hỏi lại hoặc trò chuyện)
    // Hiển thị trực tiếp câu hỏi của AI để người dùng biết mà trả lời
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(aiMessage),
        duration: const Duration(seconds: 5), // Cho người dùng thời gian đọc câu hỏi
      )
    );
  }
}
        } catch (e) {
          // BẮT LỖI: Nếu API lỗi, phải tắt loading và báo cho người dùng
          debugPrint("Lỗi khi xử lý giọng nói với AI: $e");
          if (context.mounted) {
            Navigator.pop(context); // Tắt loading
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Đã có lỗi hệ thống xảy ra, vui lòng thử lại.'),
              ),
            );
          }
        }
      }
    } finally {
      _isProcessingVoice = false;
    }
  }

  // --- DASHBOARD: CHỈNH SỬA LOGIC HIỂN THỊ ---
  Widget _buildDashboard() {
    final upcomingAppointments =
        (_allNotes
                .where((n) => n.hasAppointment && !n.isPastAppointment)
                .toList()
              ..sort((a, b) => a.time.compareTo(b.time)))
            .take(3)
            .toList();

    // 2. Ghi chú: Lấy TOÀN BỘ (bao gồm cả Lịch hẹn, vì Lịch hẹn cũng là một dạng Ghi chú)
    // Sắp xếp theo ID giảm dần (mới nhất lên đầu)
    final recentNotes = _allNotes.toList()
      ..sort((a, b) => b.time.compareTo(a.time));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Lịch hẹn sắp tới',
            onTap: () => setState(() {
              _selectedIndex = 2;
              _appointmentFilter = "all";
            }),
          ),
          const SizedBox(height: 10),
          upcomingAppointments.isEmpty
              ? _buildEmptyState(
                  "Không có lịch hẹn nào",
                  Icons.notifications_off_outlined,
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: upcomingAppointments.length,
                  itemBuilder: (ctx, i) => SmartCard(
                    title: upcomingAppointments[i].title,
                    content: upcomingAppointments[i].content,
                    date: upcomingAppointments[i].date,
                    time: upcomingAppointments[i].time,
                    isLinkedAppointment: true,
                    isPastAppointment:
                        upcomingAppointments[i].isPastAppointment,
                    onEdit: () => _openNoteForm(
                      context,
                      existingNote: upcomingAppointments[i],
                    ),
                    onDelete: () => _handleDelete(upcomingAppointments[i].id!),
                  ),
                ),
          const SizedBox(height: 5),
          SectionHeader(
            title: 'Ghi chú gần đây',
            onTap: () => setState(() => _selectedIndex = 0),
          ),
          const SizedBox(height: 5),
          recentNotes.isEmpty
              ? _buildEmptyState("Chưa có ghi chú nào", Icons.note_add_outlined)
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: recentNotes.take(4).length,
                  itemBuilder: (ctx, i) => SmartCard(
                    title: recentNotes[i].title,
                    content: recentNotes[i].content,
                    date: recentNotes[i].date,
                    time: recentNotes[i].time,
                    isLinkedAppointment: recentNotes[i].hasAppointment,
                    isPastAppointment: recentNotes[i].isPastAppointment,
                    onEdit: () =>
                        _openNoteForm(context, existingNote: recentNotes[i]),
                    onDelete: () => _handleDelete(recentNotes[i].id!),
                  ),
                ),
          const SizedBox(height: 50),
        ],
      ),
    );
  }

  void _updateFilteredList() {
    List<Note> data = [];

    if (_selectedIndex == 0) {
      // tab ghi chú
      switch (_noteFilter) {
        case "all":
          data = _recentNotes;
          break;

        case "appointment":
          data = _recentNotes.where((n) => n.hasAppointment).toList();
          break;

        case "note":
          data = _recentNotes.where((n) => !n.hasAppointment).toList();
          break;
      }
    } else if (_selectedIndex == 2) {
      // tab lịch hẹn
      switch (_appointmentFilter) {
        case "all":
          data = _allNotes.where((n) => n.hasAppointment).toList();
          break;

        case "upcoming":
          data = _allNotes
              .where((n) => n.hasAppointment && !n.isPastAppointment)
              .toList();
          break;

        case "past":
          data = _allNotes
              .where((n) => n.hasAppointment && n.isPastAppointment)
              .toList();
          break;
      }

      data.sort((a, b) => a.time.compareTo(b.time));
    }

    // _filteredData = data;
  }

  // --- DANH SÁCH CHUNG: CHỈNH SỬA LOGIC ---
  Widget _buildAllList({
    bool filterOnlyNotes = false,
    bool filterOnlyAppointments = false,
  }) {
    List data = [];
    String title = "";
    IconData emptyIcon = Icons.inbox;

    if (filterOnlyAppointments) {
      final now = DateTime.now();

      switch (_appointmentFilter) {
        case "today":
          data = _allNotes.where((n) {
            if (!n.hasAppointment) return false;
            final sameDay =
                n.time.year == now.year &&
                n.time.month == now.month &&
                n.time.day == now.day;

            return sameDay && !n.isPastAppointment;
          }).toList();
          break;

        case "week":
          final nextWeek = now.add(const Duration(days: 7));
          data = _allNotes
              .where(
                (n) =>
                    n.hasAppointment &&
                    n.time.isAfter(now) &&
                    n.time.isBefore(nextWeek),
              )
              .toList();
          break;

        case "past":
          data = _allNotes
              .where((n) => n.hasAppointment && n.isPastAppointment)
              .toList();
          break;

        case "all":
          data = _allNotes.where((n) => n.hasAppointment).toList();
          break;

        default:
          data = _allNotes
              .where((n) => n.hasAppointment && !n.isPastAppointment)
              .toList();
      }

      title = "Tất cả Lịch hẹn";
      emptyIcon = Icons.notifications_off_outlined;
    } else {
      // Tab Ghi chú: HIỆN TẤT CẢ (Lịch hẹn + Ghi chú thường)
      switch (_noteFilter) {
        case "normal":
          data = _allNotes.where((n) => !n.hasAppointment).toList();
          break;
        case "withAppointment":
          data = _allNotes.where((n) => n.hasAppointment).toList();
          break;
        case "pastAppointment":
          data = _allNotes
              .where((n) => n.hasAppointment && n.isPastAppointment)
              .toList();
          break;
        default:
          data = _allNotes.toList();
      }
      title = "Tất cả Ghi chú";
      emptyIcon = Icons.note_add_outlined;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "$title (${data.length})",
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 2),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.filter_alt_outlined),
                    tooltip: "Lọc",
                    onPressed: () => _openFilterSheet(),
                  ),

                  const SizedBox(width: 6),

                  if (!_isSelectionMode)
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        setState(() => _isSelectionMode = true);
                      },
                      child: const Text("Chọn"),
                    )
                  else ...[
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _toggleSelectAll(data),
                      child: Text(
                        _selectedIds.length == data.length
                            ? "Bỏ chọn hết"
                            : "Chọn hết",
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        setState(() {
                          _isSelectionMode = false;
                          _selectedIds.clear();
                        });
                      },
                      child: const Text("Hủy"),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _selectedIds.isEmpty
                          ? null
                          : _handleDeleteMultiple,
                      child: Text(
                        "Xóa (${_selectedIds.length})",
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 4),

        Expanded(
          child: data.isEmpty
              ? _buildEmptyState("Danh sách trống", emptyIcon)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  itemCount: data.length,
                  itemBuilder: (context, index) {
                    final note = data[index];
                    if (filterOnlyAppointments) {
                      // Giao diện Lịch hẹn
                      return GestureDetector(
                        onLongPress: () {
                          if (!_isSelectionMode) {
                            setState(() {
                              _isSelectionMode = true;
                              _selectedIds.add(note.id!);
                            });
                          }
                        },
                        onTap: () {
                          if (_isSelectionMode) {
                            setState(() {
                              if (_selectedIds.contains(note.id)) {
                                _selectedIds.remove(note.id);
                              } else {
                                _selectedIds.add(note.id!);
                              }
                            });
                          }
                        },
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildAnimatedCheckbox(note.id!),
                            Expanded(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  color: _selectedIds.contains(note.id)
                                      ? Colors.blue.withValues(alpha: 0.08)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: SmartCard(
                                  title: note.title,
                                  content: note.content,
                                  date: note.date,
                                  time: note.time,
                                  isLinkedAppointment: true,
                                  isPastAppointment: note.isPastAppointment,
                                  onEdit: () => _openNoteForm(
                                    context,
                                    existingNote: note,
                                  ),
                                  onDelete: () => _handleDelete(note.id!),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    } else {
                      // Giao diện Ghi chú (Dùng cho cả Note thường và Lịch hẹn trong tab này)
                      return GestureDetector(
                        onLongPress: () {
                          if (!_isSelectionMode) {
                            setState(() {
                              _isSelectionMode = true;
                              _selectedIds.add(note.id!);
                            });
                          }
                        },
                        onTap: () {
                          if (_isSelectionMode) {
                            setState(() {
                              if (_selectedIds.contains(note.id)) {
                                _selectedIds.remove(note.id);
                              } else {
                                _selectedIds.add(note.id!);
                              }
                            });
                          }
                        },
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildAnimatedCheckbox(note.id!),
                            Expanded(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  color: _selectedIds.contains(note.id)
                                      ? Colors.blue.withValues(alpha: 0.08)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: SmartCard(
                                  title: note.title,
                                  content: note.content,
                                  date: note.dateOnly,
                                  time: note.time,
                                  isFullWidth: true,
                                  isLinkedAppointment: note.hasAppointment,
                                  isPastAppointment: note.isPastAppointment,
                                  onEdit: () => _openNoteForm(
                                    context,
                                    existingNote: note,
                                  ),
                                  onDelete: () => _handleDelete(note.id!),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                ),
        ),
        const SizedBox(height: 65),
      ],
    );
  }

  void _openFilterSheet() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return _selectedIndex == 0
            ? _buildNoteFilterOptions()
            : _buildAppointmentFilterOptions();
      },
    );

    if (result != null) {
      setState(() {
        if (_selectedIndex == 0) {
          _noteFilter = result;
        } else if (_selectedIndex == 2) {
          _appointmentFilter = result;
        }
      });
    }
  }

  Widget _buildNoteFilterOptions() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: const Text("Tất cả"),
          trailing: _noteFilter == "all"
              ? const Icon(Icons.check, color: Colors.green)
              : null,
          onTap: () => Navigator.pop(context, "all"),
        ),
        ListTile(
          title: const Text("Ghi chú thường"),
          trailing: _noteFilter == "normal"
              ? const Icon(Icons.check, color: Colors.green)
              : null,
          onTap: () => Navigator.pop(context, "normal"),
        ),
        ListTile(
          title: const Text("Có lịch hẹn"),
          trailing: _noteFilter == "withAppointment"
              ? const Icon(Icons.check, color: Colors.green)
              : null,
          onTap: () => Navigator.pop(context, "withAppointment"),
        ),
        ListTile(
          title: const Text("Lịch hẹn đã qua"),
          trailing: _noteFilter == "pastAppointment"
              ? const Icon(Icons.check, color: Colors.green)
              : null,
          onTap: () => Navigator.pop(context, "pastAppointment"),
        ),
      ],
    );
  }

  Widget _buildAppointmentFilterOptions() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: const Text("Tất cả"),
          trailing: _appointmentFilter == "all"
              ? const Icon(Icons.check, color: Colors.green)
              : null,
          onTap: () => Navigator.pop(context, "all"),
        ),
        ListTile(
          title: const Text("Sắp tới"),
          trailing: _appointmentFilter == "upcoming"
              ? const Icon(Icons.check, color: Colors.green)
              : null,
          onTap: () => Navigator.pop(context, "upcoming"),
        ),
        ListTile(
          title: const Text("Hôm nay"),
          trailing: _appointmentFilter == "today"
              ? const Icon(Icons.check, color: Colors.green)
              : null,
          onTap: () => Navigator.pop(context, "today"),
        ),
        ListTile(
          title: const Text("7 ngày tới"),
          trailing: _appointmentFilter == "week"
              ? const Icon(Icons.check, color: Colors.green)
              : null,
          onTap: () => Navigator.pop(context, "week"),
        ),
        ListTile(
          title: const Text("Đã qua"),
          trailing: _appointmentFilter == "past"
              ? const Icon(Icons.check, color: Colors.green)
              : null,
          onTap: () => Navigator.pop(context, "past"),
        ),
      ],
    );
  }

  Widget _buildAnimatedCheckbox(int id) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: _isSelectionMode ? 40 : 0,
      child: _isSelectionMode
          ? Checkbox(
              value: _selectedIds.contains(id),
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    _selectedIds.add(id);
                  } else {
                    _selectedIds.remove(id);
                  }
                });
              },
            )
          : null,
    );
  }

  Future<void> _handleDeleteMultiple() async {
    bool confirm =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Xác nhận xóa"),
            content: Text(
              "Bạn sắp xóa ${_selectedIds.length} mục. Hành động này không thể hoàn tác.",
            ),
            actions: [
              TextButton(
                child: const Text("Hủy"),
                onPressed: () => Navigator.pop(ctx, false),
              ),
              TextButton(
                child: const Text("Xóa", style: TextStyle(color: Colors.red)),
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    for (final id in _selectedIds) {
      await AppointmentService.cancelAlarm(id);
      await DbConnector.instance.deleteNote(id);
    }

    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });

    _loadDataFromDB();
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 50, color: Colors.grey.shade300),
          const SizedBox(height: 10),
          Text(message, style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

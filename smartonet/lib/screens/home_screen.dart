import 'dart:async';
import 'dart:io';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';
import 'package:alarm/alarm.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import '../services/dbconnector.dart';
import '../database/models.dart';
import '../services/alarm_service.dart';
import '../screens/alarm_screen.dart';
import '../services/audio_service.dart';
import '../screens/permission_screen.dart';
import '../utils/notification.dart';
import '../services/permission_service.dart';

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
    setState(() {
      _allNotes = notes;
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
          const CircleAvatar(
            backgroundColor: Color(0xFF448AFF),
            child: Icon(Icons.person, color: Colors.white),
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
      floatingActionButton: _buildCustomFAB(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
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
    return SafeArea(
      child: Container(
        height: 55,
        width: 220,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: const Color(0xFFE8EAF6),
          borderRadius: BorderRadius.circular(30),
          clipBehavior: Clip.hardEdge,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _openNoteForm(context),
                  child: const Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.edit, color: Color(0xFF3F51B5), size: 20),
                        SizedBox(width: 8),
                        Text(
                          "Thủ công",
                          style: TextStyle(
                            color: Color(0xFF3F51B5),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 30, color: Colors.grey),
              Expanded(
                child: InkWell(
                  onTap: () {},
                  child: const Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mic, color: Colors.redAccent, size: 20),
                        SizedBox(width: 8),
                        Text(
                          "Giọng nói",
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
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
      ),
    );
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
            onTap: () => setState(() => _selectedIndex = 2),
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
                  itemBuilder: (ctx, i) => ReminderCard(
                    title: upcomingAppointments[i].title,
                    content: upcomingAppointments[i].content,
                    date: upcomingAppointments[i].date,
                    time: upcomingAppointments[i].time,
                    isPast: upcomingAppointments[i].isPastAppointment,
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
                  itemBuilder: (ctx, i) => NoteCard(
                    title: recentNotes[i].title,
                    content: recentNotes[i].content,
                    date: recentNotes[i].date,
                    time: recentNotes[i].time,
                    isPastAppointment: recentNotes[i].isPastAppointment,
                    isLinkedAppointment: recentNotes[i].hasAppointment,
                    onEdit: () =>
                        _openNoteForm(context, existingNote: recentNotes[i]),
                    onDelete: () => _handleDelete(recentNotes[i].id!),
                  ),
                ),
          const SizedBox(height: 80),
        ],
      ),
    );
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
      // Tab Lịch hẹn: Chỉ hiện cái có giờ
      final now = DateTime.now();

      switch (_appointmentFilter) {
        case "today":
          data = _allNotes
              .where(
                (n) =>
                    n.hasAppointment &&
                    n.time.year == now.year &&
                    n.time.month == now.month &&
                    n.time.day == now.day,
              )
              .toList();
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

        default: // upcoming
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
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.filter_alt_outlined),
                tooltip: "Lọc",
                onPressed: () => _openFilterSheet(),
              ),

              if (!_isSelectionMode)
                TextButton(
                  onPressed: () {
                    setState(() => _isSelectionMode = true);
                  },
                  child: const Text("Chọn"),
                )
              else ...[
                TextButton(
                  onPressed: () => _toggleSelectAll(data),
                  child: Text(
                    _selectedIds.length == data.length
                        ? "Bỏ chọn hết"
                        : "Chọn hết",
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isSelectionMode = false;
                      _selectedIds.clear();
                    });
                  },
                  child: const Text("Hủy"),
                ),
                TextButton(
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
        ),
        Flexible(
          child: data.isEmpty
              ? _buildEmptyState("Danh sách trống", emptyIcon)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
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
                                child: ReminderCard(
                                  title: note.title,
                                  content: note.content,
                                  date: note.date,
                                  time: note.time,
                                  isPast: note.isPastAppointment,
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
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GestureDetector(
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
                                  child: NoteCard(
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
                        ),
                      );
                    }
                  },
                ),
        ),
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

class NoteFormDialog extends StatefulWidget {
  final Note? noteData;
  final Function(
    String title,
    String content,
    DateTime? pickedDate,
    TimeOfDay? pickedTime,
    String? audioPath,
    double volume,
  )
  onSubmit;
  const NoteFormDialog({super.key, this.noteData, required this.onSubmit});

  @override
  State<NoteFormDialog> createState() => _NoteFormDialogState();
}

class _NoteFormDialogState extends State<NoteFormDialog> {
  late TextEditingController _titleCtrl;
  late TextEditingController _contentCtrl;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String? _selectedAudioPath;
  double _volume = 0.5;
  Timer? _debounceTimer;
  Timer? _stopTimer;
  double? _originalSystemVolume;
  bool _isPreviewPlaying = false;
  late FocusNode _titleFocusNode;
  String _defaultTitle = "Ghi chú mới";
  bool _isUsingDefaultTitle = true;
  late DateTime _defaultDate;
  String? _timeError;

  @override
  void initState() {
    super.initState();

    _titleCtrl = TextEditingController(
      text: widget.noteData?.title ?? _defaultTitle,
    );
    _contentCtrl = TextEditingController(text: widget.noteData?.content ?? '');

    _isUsingDefaultTitle = widget.noteData?.title == null;

    _titleFocusNode = FocusNode();
    _titleFocusNode.addListener(() {
      if (!mounted) return;
      if (_titleFocusNode.hasFocus) {
        if (_isUsingDefaultTitle) {
          _titleCtrl.clear();
          _isUsingDefaultTitle = false;
        }
      } else {
        if (_titleCtrl.text.trim().isEmpty) {
          _titleCtrl.text = _defaultTitle;
          _isUsingDefaultTitle = true;
        }
      }
    });

    _defaultDate = DateTime.now();

    if (widget.noteData != null) {
      final note = widget.noteData!;

      _selectedAudioPath = note.alarmAudioPath;
      _volume = note.volume;

      if (note.hasAppointment) {
        final dt = note.time;
        _selectedDate = DateTime(dt.year, dt.month, dt.day);
        _selectedTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
      } else {
        // ⭐ NOTE THƯỜNG → giữ ngày cũ từ time, KHÔNG dùng DateTime.now()
        final dt = note.time;
        _selectedDate = DateTime(dt.year, dt.month, dt.day);
        _selectedTime = null; // không có giờ hẹn
      }
    } else {
      // NOTE MỚI
      _selectedDate = _defaultDate;
    }

    AudioService().init();

    _initVolumeController();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _titleFocusNode.dispose();
    AudioService().stopPreview();
    FlutterVolumeController.removeListener();
    _debounceTimer?.cancel();
    _stopTimer?.cancel();
    super.dispose();
  }

  void _updateDefaultTitleBasedOnTime() {
    final bool hasTime = _selectedTime != null;

    final String newDefault = hasTime ? "Lịch nhắc mới" : "Ghi chú mới";

    // Nếu default không đổi thì thôi
    if (_defaultTitle == newDefault) return;

    _defaultTitle = newDefault;

    // CHỈ cập nhật UI nếu user chưa nhập gì riêng
    if (_isUsingDefaultTitle) {
      setState(() {
        _titleCtrl.text = _defaultTitle;
      });
    }
  }

  void _validatePickedDateTime() {
    if (_selectedDate == null || _selectedTime == null) {
      _timeError = null;
      return;
    }

    final picked = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    final now = DateTime.now();

    final nowRounded = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );

    if (picked.isBefore(nowRounded)) {
      _timeError = "Thời gian được chọn đã trôi qua";
    } else {
      _timeError = null;
    }
  }

  Future<void> _initVolumeController() async {
    if (Platform.isAndroid) {
      await FlutterVolumeController.setAndroidAudioStream(
        stream: AudioStream.alarm,
      );
    }

    _originalSystemVolume ??= await FlutterVolumeController.getVolume();

    if (widget.noteData == null) {
      _volume = 1.0;
    } else {
      _volume = widget.noteData?.volume ?? 1.0;
    }

    setState(() {});
  }

  void _onVolumeChanged(double newVolume) {
    setState(() {
      _volume = newVolume;
    });

    _debounceTimer?.cancel();
    _stopTimer?.cancel();
    AudioService().stopPreview();
    _isPreviewPlaying = false;

    _debounceTimer = Timer(const Duration(milliseconds: 200), () async {
      await FlutterVolumeController.setVolume(
        newVolume,
        stream: AudioStream.alarm,
      );

      String source =
          _selectedAudioPath ?? 'assets/Sounds/Default/alarm_digital.wav';
      AudioService().playPreview(source: source);
      _isPreviewPlaying = true;

      _stopTimer = Timer(const Duration(seconds: 3), () {
        AudioService().stopPreview();
        _isPreviewPlaying = false;
      });
    });
  }

  // String _getAudioDisplayName() {
  //   if (_selectedAudioPath == null) {
  //     return "Mặc định hệ thống";
  //   }
  //   return _selectedAudioPath!.split('/').last;
  // }

  String _getAudioDisplayName() {
    if (_selectedAudioPath == null) {
      return "Mặc định hệ thống";
    }
    String name = _selectedAudioPath!.split('/').last;
    // Cắt bỏ timestamp nếu là nhạc do người dùng thêm
    if (name.contains('_')) {
      final parts = name.split('_');
      if (parts.length > 1) {
        name = parts.sublist(1).join('_');
      }
    }
    return name;
  }

  void _openFullEditor(BuildContext context) {
    final tempController = TextEditingController(text: _contentCtrl.text);
    final tempTitleController = TextEditingController(text: _titleCtrl.text);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.85,
            child: Column(
              children: [
                // Thanh kéo
                Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                const Text(
                  "Soạn nội dung",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 12),

                TextField(
                  controller: tempTitleController,
                  decoration: InputDecoration(
                    labelText: "Tiêu đề",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.title),
                  ),
                ),

                const SizedBox(height: 12),

                // Ô nhập lớn
                Expanded(
                  child: TextField(
                    controller: tempController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: InputDecoration(
                      hintText: "Nhập nội dung chi tiết...",
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Nút lưu
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      setState(() {
                        final newTitle = tempTitleController.text.trim();
                        if (newTitle.isEmpty) {
                          _titleCtrl.text = _defaultTitle;
                          _isUsingDefaultTitle = true;
                        } else {
                          _titleCtrl.text = newTitle;
                          _isUsingDefaultTitle = false;
                        }
                        _contentCtrl.text = tempController.text;
                      });
                      Navigator.pop(context);
                    },
                    child: const Text("Lưu nội dung"),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool showMusicOption = _selectedDate != null && _selectedTime != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.noteData == null ? "Tạo mới" : "Chỉnh sửa",
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _titleCtrl,
                focusNode: _titleFocusNode,
                decoration: InputDecoration(
                  labelText: 'Tiêu đề',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.title),
                ),
              ),
              const SizedBox(height: 15),
              Stack(
                children: [
                  TextField(
                    controller: _contentCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: "Nội dung ghi chú...",
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.fromLTRB(12, 12, 48, 12),
                    ),
                  ),

                  // ✏️ Nút tròn góc phải
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.blue.shade50,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _openFullEditor(context),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.edit, size: 18, color: Colors.blue),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Đặt lịch hẹn (Tùy chọn):",
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 0),
              if (_timeError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _timeError!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(
                        _selectedDate == null
                            ? "Chọn ngày"
                            : "${_selectedDate!.day}/${_selectedDate!.month}",
                      ),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate ?? _defaultDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                        );

                        if (d != null) {
                          setState(() {
                            _selectedDate = d;
                            _validatePickedDateTime();
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time, size: 16),
                      label: Text(
                        _selectedTime == null
                            ? "Chọn giờ"
                            : "${_selectedTime!.hour}:${_selectedTime!.minute.toString().padLeft(2, '0')}",
                      ),
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: _selectedTime ?? TimeOfDay.now(),
                        );
                        if (t != null) {
                          setState(() {
                            _selectedTime = t;
                            _validatePickedDateTime();
                            _updateDefaultTitleBasedOnTime();
                          });
                        }
                      },
                    ),
                  ),
                  if (_selectedTime != null)
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => setState(() {
                        _selectedTime = null;
                        _selectedAudioPath = null;
                        _timeError = null;
                        _updateDefaultTitleBasedOnTime();
                      }),
                    ),
                ],
              ),
              if (showMusicOption) ...[
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.music_note, color: Colors.blue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Âm thanh báo thức:",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              _getAudioDisplayName(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blueAccent,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          // Tắt nhạc preview đang phát (nếu có) trước khi mở Dialog
                          _debounceTimer?.cancel();
                          _stopTimer?.cancel();
                          if (_isPreviewPlaying) {
                            await AudioService().stopPreview();
                            _isPreviewPlaying = false;
                          }
                          if (!context.mounted) return;
                          // Mở BottomSheet Chọn Nhạc
                          final String? newPath = await showModalBottomSheet<String>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (context) => SoundSelectionSheet(
                              currentSelection: _selectedAudioPath ?? 'assets/Sounds/Default/alarm_digital.wav',
                            ),
                          );
                          if (!context.mounted) return;                          
                          if (newPath != null) {
                            setState(() {
                              _selectedAudioPath = newPath;
                            });
                          }
                        },
                        child: const Text("Đổi nhạc"),
                      ),
                      // TextButton(
                      //   onPressed: () async {
                      //     final String? newPath = await AudioService()
                      //         .pickAudioFile();
                      //     if (newPath != null) {
                      //       setState(() {
                      //         _selectedAudioPath = newPath;
                      //       });
                      //     }
                      //   },
                      //   child: const Text("Đổi nhạc"),
                      // ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      Icons.volume_mute,
                      size: 20,
                      color: Colors.blue.withValues(alpha: 0.6),
                    ),
                    Expanded(
                      child: Slider(
                        value: _volume,
                        min: 0.0,
                        max: 1.0,
                        divisions: 100,
                        label: "${(_volume * 100).round()}%",
                        activeColor: Colors.blue,
                        onChanged: _onVolumeChanged,
                      ),
                    ),
                    Icon(Icons.volume_up, size: 20, color: Colors.blue),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  child: const Text("Lưu"),
                  onPressed: () async {
                    String finalTitle = _titleCtrl.text.trim().isEmpty
                        ? _defaultTitle
                        : _titleCtrl.text.trim();

                    _debounceTimer?.cancel();
                    _stopTimer?.cancel();

                    if (_isPreviewPlaying) {
                      await AudioService().stopPreview();
                      _isPreviewPlaying = false;
                    }

                    if (_originalSystemVolume != null) {
                      await FlutterVolumeController.setVolume(
                        _originalSystemVolume!,
                        stream: AudioStream.alarm,
                      );
                    }

                    widget.onSubmit(
                      finalTitle,
                      _contentCtrl.text,
                      _selectedDate,
                      _selectedTime,
                      _selectedAudioPath,
                      _volume,
                    );

                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SoundSelectionSheet extends StatefulWidget {
  final String? currentSelection;
  const SoundSelectionSheet({super.key, this.currentSelection});

  @override
  State<SoundSelectionSheet> createState() => _SoundSelectionSheetState();
}

class _SoundSelectionSheetState extends State<SoundSelectionSheet> {
  List<String> _defaultSounds = [];
  List<String> _customSounds = [];
  bool _isLoading = true;
  String? _tempSelectedPath;
  String? _currentlyPlayingPath;

  @override
  void initState() {
    super.initState();
    _tempSelectedPath = widget.currentSelection;
    _loadSounds();
  }

  Future<void> _loadSounds() async {
    setState(() => _isLoading = true);
    final defaults = await AudioService().getDefaultSounds();
    final customs = await AudioService().getCustomSounds();
    if (mounted) {
      setState(() {
        _defaultSounds = defaults;
        _customSounds = customs;
        _isLoading = false;
      });
    }
  }

  void _togglePlayPreview(String path) async {
    if (_currentlyPlayingPath == path) {
      await AudioService().stopPreview();
      setState(() => _currentlyPlayingPath = null);
    } else {
      await AudioService().playPreview(source: path);
      if (!mounted) return;
      setState(() => _currentlyPlayingPath = path);
    }
  }

  @override
  void dispose() {
    AudioService().stopPreview();
    super.dispose();
  }

  Widget _buildSoundTile(String path, bool isCustom) {
    String displayName = path.split('/').last;
    if (isCustom) {
      // Cắt bỏ timestamp nếu có
      final parts = displayName.split('_');
      if (parts.length > 1) {
        displayName = parts.sublist(1).join('_');
      }
    }

    bool isSelected = _tempSelectedPath == path;
    bool isPlaying = _currentlyPlayingPath == path;

    return ListTile(
      leading: IconButton(
        icon: Icon(
          isPlaying ? Icons.stop_circle : Icons.play_circle_fill,
          color: isPlaying ? Colors.red : Colors.blue,
        ),
        onPressed: () => _togglePlayPreview(path),
      ),
      title: Text(
        displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.blue : Colors.black87,
        ),
      ),
      trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.blue) : null,
      onTap: () {
        setState(() => _tempSelectedPath = path);
        _togglePlayPreview(path);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              "Chọn âm thanh",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text("Hệ thống", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                      ..._defaultSounds.map((p) => _buildSoundTile(p, false)),
                      
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text("Của bạn", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                      ..._customSounds.map((p) => _buildSoundTile(p, true)),
                      
                      if (_customSounds.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text("Chưa có âm thanh cá nhân.", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                        ),
                    ],
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text("Thêm"),
                  onPressed: () async {
                    final newPath = await AudioService().addCustomSound();
                    if (newPath != null) {
                      setState(() => _tempSelectedPath = newPath);
                      await _loadSounds();
                      _togglePlayPreview(newPath);
                    }
                  },
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Hủy", style: TextStyle(color: Colors.grey)),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(context, _tempSelectedPath);
                  },
                  child: const Text("Xác nhận"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MusicLibraryDialog extends StatefulWidget {
  const MusicLibraryDialog({super.key});

  @override
  State<MusicLibraryDialog> createState() => _MusicLibraryDialogState();
}

class _MusicLibraryDialogState extends State<MusicLibraryDialog> {
  List<String> _defaultSounds = [];
  List<String> _customSounds = [];
  bool _isLoading = true;

  bool _isSelectionMode = false;
  final Set<String> _selectedPaths = {};
  String? _currentlyPlayingPath;

  @override
  void initState() {
    super.initState();
    _loadSounds();
  }

  Future<void> _loadSounds() async {
    setState(() => _isLoading = true);
    final defaults = await AudioService().getDefaultSounds();
    final customs = await AudioService().getCustomSounds();

    if (mounted) {
      setState(() {
        _defaultSounds = defaults;
        _customSounds = customs;
        _isLoading = false;
        _isSelectionMode = false;
        _selectedPaths.clear();
      });
    }
  }

  void _togglePlayPreview(String path) async {
    if (_currentlyPlayingPath == path) {
      await AudioService().stopPreview();
      setState(() => _currentlyPlayingPath = null);
    } else {
      await AudioService().playPreview(source: path);
      setState(() => _currentlyPlayingPath = path);
    }
  }

  @override
  void dispose() {
    AudioService().stopPreview();
    super.dispose();
  }

  Future<void> _handleAddMusic() async {
    final newPath = await AudioService().addCustomSound();
    if (newPath != null) {
      _loadSounds();
    }
  }

  Future<void> _handleDeleteSelected() async {
    bool confirm =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Xác nhận xóa"),
            content: Text(
              "Bạn sắp xóa ${_selectedPaths.length} âm thanh. Hành động này không thể hoàn tác.",
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
      await AudioService().deleteCustomSounds(_selectedPaths.toList());
      _loadSounds();
    }
  }

  Widget _buildSoundTile(String path, bool isCustom) {
    // Ẩn đoạn timestamp khi hiển thị tên file để nhìn đẹp hơn
    String displayName = path.split('/').last;
    if (isCustom) {
      // Cắt bỏ phần timestamp (ví dụ: 1715012345_tenbaihat.mp3 -> tenbaihat.mp3)
      final parts = displayName.split('_');
      if (parts.length > 1) {
        displayName = parts.sublist(1).join('_');
      }
    }

    bool isSelected = _selectedPaths.contains(path);
    bool isPlaying = _currentlyPlayingPath == path;

    return ListTile(
      leading: _isSelectionMode && isCustom
          ? Checkbox(
              value: isSelected,
              onChanged: (val) {
                setState(() {
                  val == true
                      ? _selectedPaths.add(path)
                      : _selectedPaths.remove(path);
                });
              },
            )
          : IconButton(
              icon: Icon(
                isPlaying ? Icons.stop_circle : Icons.play_circle_fill,
                color: isPlaying ? Colors.red : Colors.blue,
              ),
              onPressed: () => _togglePlayPreview(path),
            ),
      title: Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () {
        if (_isSelectionMode && isCustom) {
          setState(() {
            isSelected ? _selectedPaths.remove(path) : _selectedPaths.add(path);
          });
        } else {
          _togglePlayPreview(path);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              "Kho nhạc",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            "Hệ thống",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        ..._defaultSounds.map(
                          (path) => _buildSoundTile(path, false),
                        ),

                        Padding(
                          padding: const EdgeInsets.only(
                            top: 16.0,
                            bottom: 8.0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Của bạn",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              if (_customSounds.isNotEmpty && _isSelectionMode)
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      if (_selectedPaths.length ==
                                          _customSounds.length) {
                                        _selectedPaths.clear();
                                      } else {
                                        _selectedPaths.addAll(_customSounds);
                                      }
                                    });
                                  },
                                  child: Text(
                                    _selectedPaths.length ==
                                            _customSounds.length
                                        ? "Bỏ chọn hết"
                                        : "Chọn hết",
                                  ),
                                ),
                            ],
                          ),
                        ),
                        ..._customSounds.map(
                          (path) => _buildSoundTile(path, true),
                        ),
                        if (_customSounds.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text(
                              "Chưa có âm thanh nào",
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),

            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (!_isSelectionMode) ...[
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text("Thêm nhạc"),
                    onPressed: _handleAddMusic,
                  ),
                  if (_customSounds.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text(
                        "Xóa",
                        style: TextStyle(color: Colors.red),
                      ),
                      onPressed: () => setState(() => _isSelectionMode = true),
                    ),
                ] else ...[
                  TextButton(
                    onPressed: () => setState(() {
                      _isSelectionMode = false;
                      _selectedPaths.clear();
                    }),
                    child: const Text("Hủy"),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    onPressed: _selectedPaths.isEmpty
                        ? null
                        : _handleDeleteSelected,
                    child: Text(
                      "Xóa (${_selectedPaths.length})",
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
//          CUSTOM CARDS
// ==========================================
class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onTap;
  const SectionHeader({super.key, required this.title, required this.onTap});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      TextButton(onPressed: onTap, child: const Text('Xem tất cả')),
    ],
  );
}

class ReminderCard extends StatelessWidget {
  final String title, content;
  final DateTime date, time;
  final VoidCallback? onEdit, onDelete;
  final bool isPast;
  const ReminderCard({
    super.key,
    required this.title,
    required this.content,
    required this.date,
    required this.time,
    this.onEdit,
    this.onDelete,
    this.isPast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.alarm, color: Colors.red),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (isPast)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text("Đã qua", style: TextStyle(fontSize: 10)),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "${date.day}/${date.month} • ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            if (content.isNotEmpty)
              Text(content, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onEdit != null)
              IconButton(
                icon: const Icon(Icons.edit, size: 20, color: Colors.orange),
                onPressed: onEdit,
              ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(
                  Icons.delete,
                  size: 20,
                  color: Colors.redAccent,
                ),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}

class NoteCard extends StatelessWidget {
  final String title, content;
  final DateTime? date;
  final DateTime? time;
  final bool isFullWidth;
  final bool isLinkedAppointment;
  final VoidCallback? onEdit, onDelete;
  final bool isPastAppointment;

  const NoteCard({
    super.key,
    required this.title,
    required this.content,
    this.date,
    this.time,
    this.isFullWidth = false,
    this.isLinkedAppointment = false,
    this.onEdit,
    this.onDelete,
    this.isPastAppointment = false,
  });

  @override
  Widget build(BuildContext context) {
    String timeStr = "";
    if (date != null && time != null) {
      if (isLinkedAppointment) {
        // TRƯỜNG HỢP 1: LỊCH HẸN -> Hiện Giờ báo thức + Ngày hẹn
        final hour = time!.hour.toString().padLeft(2, '0');
        final minute = time!.minute.toString().padLeft(2, '0');
        timeStr = "$hour:$minute • ${date!.day}/${date!.month}";
      } else {
        // TRƯỜNG HỢP 2: GHI CHÚ THƯỜNG
        // Chỉ hiện Ngày người dùng chọn.
        // Giờ tạo (time) dùng để sắp xếp nhưng KHÔNG hiển thị để tránh rối.
        timeStr = "Ngày: ${date!.day}/${date!.month}";

        // Nếu bạn VẪN MUỐN hiện giờ tạo, hãy dùng định dạng khác hẳn:
        // final hour = time!.hour.toString().padLeft(2, '0');
        // final minute = time!.minute.toString().padLeft(2, '0');
        // timeStr = "${date!.day}/${date!.month} (Tạo lúc $hour:$minute)";
      }
    }

    return Card(
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- HÀNG TRÊN CÙNG: Badge + Ngày giờ + Nút bấm ---
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ====== BÊN TRÁI: BADGE + TIME ======
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Badge Note / Có hẹn
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isLinkedAppointment
                              ? Colors.orange.shade50
                              : Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isLinkedAppointment ? "Có hẹn" : "Note",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isLinkedAppointment
                                ? Colors.deepOrange
                                : Colors.blue,
                          ),
                        ),
                      ),

                      // Badge Đã qua
                      if (isPastAppointment)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            "Đã qua",
                            style: TextStyle(fontSize: 10),
                          ),
                        ),

                      // Thời gian
                      if (date != null) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 12,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 2),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 110),
                              child: Text(
                                timeStr,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                // ====== BÊN PHẢI: NÚT SỬA / XOÁ ======
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onEdit != null)
                      InkWell(
                        onTap: onEdit,
                        child: const Icon(
                          Icons.edit,
                          size: 18,
                          color: Colors.orange,
                        ),
                      ),
                    if (onDelete != null) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: onDelete,
                        child: const Icon(
                          Icons.delete,
                          size: 18,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 5),

            // --- TIÊU ĐỀ ---
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),

            // --- NỘI DUNG ---
            Text(
              content,
              maxLines: isFullWidth ? 5 : 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
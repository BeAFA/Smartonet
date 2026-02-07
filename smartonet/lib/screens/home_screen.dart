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
import '../utils/permission_banner.dart';
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
        showPermissionDialog(context, showPermanentDisable: true);
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

  void _openNoteForm(BuildContext context, {Note? existingNote}) {
    showDialog(
      context: context,
      builder: (context) {
        return NoteFormDialog(
          noteData: existingNote,
          onSubmit: (title, content, pickedDateTime, audioPath, volume) async {
            bool hasAppt = pickedDateTime != null;
            DateTime saveDate = pickedDateTime ?? DateTime.now();

            if (hasAppt) {
              final granted = await PermissionService().isNotificationGranted();

              if (!granted) {
                final prefs = await SharedPreferences.getInstance();
                final isHiddenForever =
                    prefs.getBool('hide_permission_forever') ?? false;

                if (!isHiddenForever && context.mounted) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    showPermissionDialog(context, showPermanentDisable: true);
                  });
                }
              }

              final conflict = await AppointmentService.isTimeConflict(
                saveDate,
                ignoreNoteId: existingNote?.id,
              );

              if (conflict) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Đã có lịch hẹn khác trùng giờ này"),
                      behavior: SnackBarBehavior.floating,
                      margin: EdgeInsets.symmetric(
                        horizontal: 16,
                      ), // ❌ không set bottom
                    ),
                  );
                }
                return; // ❌ DỪNG, KHÔNG LƯU
              }
            }

            // ✅ CHỈ LƯU SAU KHI KHÔNG TRÙNG
            Note noteToSave = Note(
              id: existingNote?.id,
              title: title,
              content: content,
              date: saveDate,
              time: saveDate,
              hasAppointment: hasAppt,
              alarmAudioPath: audioPath,
              volume: volume,
            );

            int id = await DbConnector.instance.saveNote(noteToSave);
            noteToSave.id = id;

            if (hasAppt) {
              await AppointmentService.scheduleAppointment(noteToSave);
            } else if (existingNote?.id != null) {
              await AppointmentService.cancelAlarm(existingNote!.id!);
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
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
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
        _allNotes
            .where((n) => n.hasAppointment && !n.isPastAppointment)
            .toList()
          ..sort((a, b) => a.time.compareTo(b.time));

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
                  itemCount: upcomingAppointments.take(3).length,
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
      data = _allNotes.where((n) => n.hasAppointment).toList()
        ..sort((a, b) => a.time.compareTo(b.time));
      title = "Tất cả Lịch hẹn";
      emptyIcon = Icons.notifications_off_outlined;
    } else {
      // Tab Ghi chú: HIỆN TẤT CẢ (Lịch hẹn + Ghi chú thường)
      data = _allNotes.toList()..sort((a, b) => a.time.compareTo(b.time));
      title = "Tất cả Ghi chú";
      emptyIcon = Icons.note_add_outlined;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: data.isEmpty
              ? _buildEmptyState("Danh sách trống", emptyIcon)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  itemCount: data.length,
                  itemBuilder: (context, index) {
                    final note = data[index];
                    if (filterOnlyAppointments) {
                      // Giao diện Lịch hẹn
                      return ReminderCard(
                        title: note.title,
                        content: note.content,
                        date: note.date,
                        time: note.time,
                        isPast: note.isPastAppointment,
                        onEdit: () =>
                            _openNoteForm(context, existingNote: note),
                        onDelete: () => _handleDelete(note.id!),
                      );
                    } else {
                      // Giao diện Ghi chú (Dùng cho cả Note thường và Lịch hẹn trong tab này)
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: NoteCard(
                          title: note.title,
                          content: note.content,
                          date: note.date,
                          isFullWidth: true,
                          isLinkedAppointment: note.hasAppointment,
                          isPastAppointment: note.isPastAppointment,
                          onEdit: () =>
                              _openNoteForm(context, existingNote: note),
                          onDelete: () => _handleDelete(note.id!),
                        ),
                      );
                    }
                  },
                ),
        ),
      ],
    );
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
    DateTime? scheduledTime,
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

    if (widget.noteData != null && widget.noteData!.hasAppointment) {
      _selectedDate = widget.noteData!.date;
    } else {
      _selectedDate = _defaultDate;
    }

    AudioService().init();

    if (widget.noteData != null && widget.noteData!.hasAppointment) {
      _selectedDate = widget.noteData!.date;
      _selectedTime = TimeOfDay.fromDateTime(widget.noteData!.time);
      _selectedAudioPath = widget.noteData?.alarmAudioPath;
      _volume = widget.noteData?.volume ?? 0.5;
    }
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

      String source = _selectedAudioPath ?? 'assets/Default/alarm_digital.wav';
      AudioService().playPreview(source: source);
      _isPreviewPlaying = true;

      _stopTimer = Timer(const Duration(seconds: 3), () {
        AudioService().stopPreview();
        _isPreviewPlaying = false;
      });
    });
  }

  String _getAudioDisplayName() {
    if (_selectedAudioPath == null) {
      return "Mặc định hệ thống";
    }
    return _selectedAudioPath!.split('/').last;
  }

  void _openFullEditor(BuildContext context) {
    final tempController = TextEditingController(text: _contentCtrl.text);

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
              const SizedBox(height: 8),
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
                          });
                          _updateDefaultTitleBasedOnTime();
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
                          final String? newPath = await AudioService()
                              .pickAudioFile();
                          if (newPath != null) {
                            setState(() {
                              _selectedAudioPath = newPath;
                            });
                          }
                        },
                        child: const Text("Đổi nhạc"),
                      ),
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
                    DateTime? finalDT;
                    if (_selectedDate != null && _selectedTime != null) {
                      finalDT = DateTime(
                        _selectedDate!.year,
                        _selectedDate!.month,
                        _selectedDate!.day,
                        _selectedTime!.hour,
                        _selectedTime!.minute,
                      );
                    }
                    widget.onSubmit(
                      finalTitle,
                      _contentCtrl.text,
                      finalDT,
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
              "${date.day}/${date.month} • ${time.hour}:${time.minute.toString().padLeft(2, '0')}",
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
  final bool isFullWidth;
  final bool isLinkedAppointment;
  final VoidCallback? onEdit, onDelete;
  final bool isPastAppointment;

  const NoteCard({
    super.key,
    required this.title,
    required this.content,
    this.date,
    this.isFullWidth = false,
    this.isLinkedAppointment = false,
    this.onEdit,
    this.onDelete,
    this.isPastAppointment = false,
  });

  @override
  Widget build(BuildContext context) {
    String timeStr = "";
    if (date != null) {
      final hour = date!.hour.toString().padLeft(2, '0');
      final minute = date!.minute.toString().padLeft(2, '0');
      timeStr = "$hour:$minute   ${date!.day}/${date!.month}";
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Cụm bên trái: Badge + Ngày giờ
                Expanded(
                  child: Row(
                    children: [
                      // Badge (Note/Có hẹn)
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
                      if (isPastAppointment) ...[
                        const SizedBox(width: 6),
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
                      ],
                      // Hiển thị Ngày giờ (Nếu có)
                      if (date != null) ...[
                        const SizedBox(width: 5),
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 2),
                        Flexible(
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
                    ],
                  ),
                ),

                // Cụm bên phải: Nút Sửa/Xóa
                Row(
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
                    const SizedBox(width: 8),
                    if (onDelete != null)
                      InkWell(
                        onTap: onDelete,
                        child: const Icon(
                          Icons.delete,
                          size: 18,
                          color: Colors.red,
                        ),
                      ),
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
              maxLines: isFullWidth ? 3 : 5,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

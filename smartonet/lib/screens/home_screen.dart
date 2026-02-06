import 'dart:async';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';
import 'package:alarm/alarm.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';
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
              await AppointmentService.scheduleAppointment(noteToSave);
            } else {
              if (existingNote != null && existingNote.id != null) {
                await AppointmentService.cancelAlarm(existingNote.id!);
              }
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
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
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
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
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

  Widget _buildCustomFAB(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 50),
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
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
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
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
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
    );
  }

  // --- DASHBOARD: CHỈNH SỬA LOGIC HIỂN THỊ ---
  Widget _buildDashboard() {
    // 1. Lịch hẹn: Chỉ lấy những cái có hasAppointment = true
    final appointments = _allNotes.where((n) => n.hasAppointment).toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    // 2. Ghi chú: Lấy TOÀN BỘ (bao gồm cả Lịch hẹn, vì Lịch hẹn cũng là một dạng Ghi chú)
    // Sắp xếp theo ID giảm dần (mới nhất lên đầu)
    final allRecentNotes = _allNotes.toList()
      ..sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));

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
          appointments.isEmpty
              ? _buildEmptyState(
                  "Không có lịch hẹn nào",
                  Icons.notifications_off_outlined,
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: appointments.take(3).length,
                  itemBuilder: (ctx, i) => ReminderCard(
                    title: appointments[i].title,
                    content: appointments[i].content,
                    date: appointments[i].date,
                    time: appointments[i].time,
                    onEdit: () =>
                        _openNoteForm(context, existingNote: appointments[i]),
                    onDelete: () => _handleDelete(appointments[i].id!),
                  ),
                ),
          const SizedBox(height: 25),
          SectionHeader(
            title: 'Ghi chú gần đây',
            onTap: () => setState(() => _selectedIndex = 0),
          ),
          const SizedBox(height: 10),
          // Bây giờ danh sách này sẽ hiển thị cả Lịch hẹn dưới dạng Card Ghi chú
          allRecentNotes.isEmpty
              ? _buildEmptyState("Chưa có ghi chú nào", Icons.note_add_outlined)
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: allRecentNotes.take(4).length,
                  itemBuilder: (ctx, i) => NoteCard(
                    title: allRecentNotes[i].title,
                    content: allRecentNotes[i].content,
                    date: allRecentNotes[i].hasAppointment
                        ? allRecentNotes[i].time
                        : null,
                    isLinkedAppointment: allRecentNotes[i].hasAppointment,
                    onEdit: () =>
                        _openNoteForm(context, existingNote: allRecentNotes[i]),
                    onDelete: () => _handleDelete(allRecentNotes[i].id!),
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
    List<Note> data = [];
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
      data = _allNotes.toList()
        ..sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));
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
                          date: note.hasAppointment ? note.time : null,
                          isFullWidth: true,
                          isLinkedAppointment:
                              note.hasAppointment, // Truyền cờ này vào
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
  final AudioPlayer _audioPlayer = AudioPlayer();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String? _selectedAudioPath;
  double _volume = 1.0;
  Timer? _debounceTimer;
  Timer? _stopTimer;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.noteData?.title ?? '');
    _contentCtrl = TextEditingController(text: widget.noteData?.content ?? '');
    if (widget.noteData != null && widget.noteData!.hasAppointment) {
      _selectedDate = widget.noteData!.date;
      _selectedTime = TimeOfDay.fromDateTime(widget.noteData!.time);
      _selectedAudioPath = widget.noteData?.alarmAudioPath;
      _volume = widget.noteData?.volume ?? 1.0;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _audioPlayer.dispose();
    _debounceTimer?.cancel();
    _stopTimer?.cancel();
    super.dispose();
  }

  void _previewVolume(double newVolume) {
    // 1. Nếu người dùng đang kéo liên tục, hủy các lệnh phát nhạc/tắt nhạc trước đó
    _debounceTimer?.cancel();
    _stopTimer?.cancel();

    // Dừng ngay lập tức âm thanh đang phát (nếu có) để tránh chồng âm
    _audioPlayer.stop();

    // 2. Bắt đầu đếm ngược 300ms (Thời gian chờ người dùng chốt volume)
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        // Cấu hình file nhạc (Nếu chưa load thì load lại)
        if (_selectedAudioPath == null) {
          await _audioPlayer.setAsset('assets/Default/alarm_digital.wav');
        } else {
          await _audioPlayer.setFilePath(_selectedAudioPath!);
        }

        double simulatedSystemMax = 1.0;
        double previewVolume = simulatedSystemMax * newVolume;

        // Set volume mới
        await _audioPlayer.setVolume(previewVolume);

        // Phát nhạc
        await _audioPlayer.play();

        // 3. Đặt lịch tự động tắt sau 2 giây (3 giây hơi lâu cho việc test volume)
        _stopTimer = Timer(const Duration(seconds: 2), () {
          _audioPlayer.stop();
        });
      } catch (e) {
        debugPrint("Lỗi preview volume: $e");
      }
    });
  }

  String _getAudioDisplayName() {
    if (_selectedAudioPath == null) {
      return "Mặc định hệ thống";
    }
    return _selectedAudioPath!.split('/').last;
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
                decoration: InputDecoration(
                  labelText: 'Tiêu đề',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.title),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _contentCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Nội dung',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
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
                          initialDate: _selectedDate ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) setState(() => _selectedDate = d);
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
                        if (t != null) setState(() => _selectedTime = t);
                      },
                    ),
                  ),
                  if (_selectedDate != null || _selectedTime != null)
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => setState(() {
                        _selectedDate = null;
                        _selectedTime = null;
                        _selectedAudioPath = null;
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
                        onChanged: (double value) {
                          if (!mounted) return;
                          setState(() {
                            _volume = value;
                          });
                          _previewVolume(_volume);
                        },
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
                  onPressed: () {
                    if (_titleCtrl.text.trim().isEmpty) return;
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
                      _titleCtrl.text,
                      _contentCtrl.text,
                      finalDT,
                      _selectedAudioPath,
                      _volume,
                    );
                    Navigator.pop(context);
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
  const ReminderCard({
    super.key,
    required this.title,
    required this.content,
    required this.date,
    required this.time,
    this.onEdit,
    this.onDelete,
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
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
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
  final DateTime? date; // 1. Thêm biến ngày giờ (có thể null)
  final bool isFullWidth;
  final bool isLinkedAppointment;
  final VoidCallback? onEdit, onDelete;

  const NoteCard({
    super.key,
    required this.title,
    required this.content,
    this.date, // 2. Thêm vào constructor
    this.isFullWidth = false,
    this.isLinkedAppointment = false,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // Helper để format giờ cho đẹp (VD: 09:05)
    String timeStr = "";
    if (date != null) {
      final hour = date!.hour.toString().padLeft(2, '0');
      final minute = date!.minute.toString().padLeft(2, '0');
      timeStr = "$hour:$minute ${date!.day}/${date!.month}";
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

                      // Hiển thị Ngày giờ (Nếu có)
                      if (date != null) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 4),
                        // Dùng Flexible để text không bị tràn nếu quá dài
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
            const SizedBox(height: 12),

            // --- TIÊU ĐỀ ---
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),

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

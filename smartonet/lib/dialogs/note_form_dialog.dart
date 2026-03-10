import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import '../database/models.dart';
import '../services/audio_service.dart';
import 'sound_selection_dialog.dart';

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

    if (mounted) {
      setState(() {});
    }
  }

  void _onVolumeChanged(double newVolume) {
    if (!mounted) return;
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
                          final String? newPath =
                              await showModalBottomSheet<String>(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (context) => SoundSelectionSheet(
                                  currentSelection:
                                      _selectedAudioPath ??
                                      'assets/Sounds/Default/alarm_digital.wav',
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
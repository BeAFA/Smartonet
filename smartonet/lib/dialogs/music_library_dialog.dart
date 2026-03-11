import 'dart:async';
import 'package:flutter/material.dart';
import '../services/audio_service.dart';

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
    if (!context.mounted) return;
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
      if (!mounted) return;
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

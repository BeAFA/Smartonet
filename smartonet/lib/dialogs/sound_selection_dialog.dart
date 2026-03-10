import 'dart:async';
import 'package:flutter/material.dart';
import '../services/audio_service.dart';

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
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: Colors.blue)
          : null,
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
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          "Hệ thống",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      ..._defaultSounds.map((p) => _buildSoundTile(p, false)),

                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          "Của bạn",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      ..._customSounds.map((p) => _buildSoundTile(p, true)),

                      if (_customSounds.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            "Chưa có âm thanh cá nhân.",
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                          ),
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
                  child: const Text(
                    "Hủy",
                    style: TextStyle(color: Colors.grey),
                  ),
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
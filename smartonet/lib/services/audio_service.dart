import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:logging/logging.dart';

class AudioService {
  static final _log = Logger('AudioService');
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;

  AudioService._internal();

  final AudioPlayer _player = AudioPlayer();
  bool _initialized = false;
  bool _isCancelRequested = false;

  final ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(children: []);
  Timer? _previewTimer;

  Future<void> init() async {
    if (_initialized) return;
    await _configureSessionUsage(AndroidAudioUsage.media);
    _initialized = true;
  }

  Future<void> _configureSessionUsage(AndroidAudioUsage usage) async {
    final session = await AudioSession.instance;
    await session.configure(
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: usage,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ),
    );
  }

  // =========================================================================
  // CÁC HÀM CŨ ĐỂ KHÔNG BỊ LỖI Ở CÁC FILE KHÁC
  // =========================================================================

  Future<void> playPreview({required String source}) async {
    await init();
    if (_player.playing) await _player.stop();
    try {
      bool isFile = source.startsWith('/') || source.contains(Platform.pathSeparator);
      if (isFile) {
        if (await File(source).exists()) {
          await _player.setFilePath(source);
        } else {
          await _player.setAsset('assets/Sounds/Default/alarm_digital.wav');
        }
      } else {
        await _player.setAsset(source);
      }
      await _player.setVolume(1.0);
      await _player.setLoopMode(LoopMode.off);
      await _player.play();
    } catch (e) {
      _log.warning("Lỗi phát nhạc preview: $e");
    }
  }

  void dispose() {
    _previewTimer?.cancel();
    _player.dispose();
  }

  Future<String?> pickAudioFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg'],
    );
    if (result != null) return result.files.single.path;
    return null;
  }

  Future<List<String>> getDefaultSounds() async {
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);
      return manifestMap.keys
          .where((key) => key.startsWith('assets/Sounds/Default/') && (key.endsWith('.mp3') || key.endsWith('.wav')))
          .toList();
    } catch (e) {
      return ['assets/Sounds/Default/alarm_digital.wav'];
    }
  }

  Future<String> _getCustomizeDirectoryPath() async {
    final directory = await getApplicationDocumentsDirectory();
    final customPath = p.join(directory.path, 'Sounds', 'Customize');
    final dir = Directory(customPath);
    if (!await dir.exists()) await dir.create(recursive: true);
    return customPath;
  }

  Future<List<String>> getCustomSounds() async {
    final path = await _getCustomizeDirectoryPath();
    final dir = Directory(path);
    List<String> sounds = [];
    if (await dir.exists()) {
      await for (var entity in dir.list()) {
        if (entity is File) sounds.add(entity.path);
      }
    }
    return sounds;
  }

  Future<String?> addCustomSound() async {
    final pickedPath = await pickAudioFile();
    if (pickedPath != null) {
      final customPath = await _getCustomizeDirectoryPath();
      final originalFileName = p.basename(pickedPath);
      final targetPath = p.join(customPath, originalFileName);
      final targetFile = File(targetPath);

      if (await targetFile.exists()) {
        _log.info("File '$originalFileName' đã tồn tại. Dùng lại file cũ.");
        return targetPath;
      }

      await File(pickedPath).copy(targetPath);
      _log.info("Đã thêm nhạc mới thành công: $originalFileName");
      return targetPath;
    }
    return null;
  }

  Future<void> deleteCustomSounds(List<String> pathsToDelete) async {
    for (String path in pathsToDelete) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<bool> deleteCustomAudioByKeyword(String keyword) async {
    final customSounds = await getCustomSounds();
    if (customSounds.isEmpty) return false;

    if (keyword.toLowerCase() == 'all' || keyword.toLowerCase() == 'tất cả') {
      await deleteCustomSounds(customSounds);
      return true;
    }

    List<String> toDelete = customSounds.where((path) {
      return p.basename(path).toLowerCase().contains(keyword.toLowerCase());
    }).toList();

    if (toDelete.isNotEmpty) {
      await deleteCustomSounds(toDelete);
      return true;
    }
    return false;
  }

  // =========================================================================
  // CÁC KÊNH THÔNG TIN CHO GIAO DIỆN MÀN HÌNH PREVIEW
  // =========================================================================
  Stream<bool> get playingStream => _player.playingStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;
  Stream<SequenceState?> get sequenceStateStream => _player.sequenceStateStream;

  Future<void> pausePreview() async {
    _previewTimer?.cancel();
    if (_player.playing) await _player.pause();
  }

  Future<void> resumePreview() async {
    if (!_player.playing) await _player.play();
  }

  Future<void> stopPreview() async {
    _previewTimer?.cancel();
    _isCancelRequested = true;
    if (_player.playing) await _player.stop();
  }

  Future<void> seek(Duration position) async => await _player.seek(position);
  Future<void> skipToNext() async => await _player.seekToNext();
  Future<void> skipToPrevious() async => await _player.seekToPrevious();

  // =========================================================================
  // HÀM PHÁT NHẠC NÂNG CẤP (DÙNG PLAYLIST ĐỂ CÓ NÚT NEXT/PREV)
  // =========================================================================
  Future<void> previewAdvanced({
    String? keyword,
    String targetType = 'both',
    int playCount = 1,
    int? durationInSeconds,
  }) async {
    _isCancelRequested = false;
    List<String> allPaths = [];
    if (targetType == 'custom' || targetType == 'both') allPaths.addAll(await getCustomSounds());
    if (targetType == 'default' || targetType == 'both') allPaths.addAll(await getDefaultSounds());

    if (keyword != null && keyword.isNotEmpty && keyword.toLowerCase() != 'all') {
      allPaths = allPaths.where((path) => p.basename(path).toLowerCase().contains(keyword.toLowerCase())).toList();
    }

    if (allPaths.isEmpty) {
      _log.warning("Không tìm thấy bài hát nào phù hợp.");
      return;
    }

    if (playCount > 0 && playCount < allPaths.length) {
      allPaths = allPaths.sublist(0, playCount);
    }

    await init();
    _previewTimer?.cancel();

    // Dựng Playlist thực thụ
    List<AudioSource> sources = [];
    for (String path in allPaths) {
      bool isFile = path.startsWith('/') || path.contains(Platform.pathSeparator);
      // Dùng 'tag' để mang tên file truyền lên UI
      if (isFile && await File(path).exists()) {
        sources.add(AudioSource.uri(Uri.file(path), tag: p.basename(path)));
      } else if (!isFile) {
        sources.add(AudioSource.asset(path, tag: p.basename(path)));
      }
    }

    await _playlist.clear();
    await _playlist.addAll(sources);
    await _player.setAudioSource(_playlist);

    await _configureSessionUsage(AndroidAudioUsage.media);
    
    try {
      await _player.setVolume(1.0);
      await _player.setLoopMode(LoopMode.off);
      _player.play();

      if (durationInSeconds == null) {
        // TRƯỜNG HỢP 1: Phát toàn bộ (Đợi nhạc chạy xong)
        await _player.playerStateStream.firstWhere(
          (state) => state.processingState == ProcessingState.completed || 
                     state.processingState == ProcessingState.idle || 
                     _isCancelRequested
        );
      } else {
        // TRƯỜNG HỢP 2: Nghe thử giới hạn thời gian (Dùng Timer nhảy bài)
        StreamSubscription? seqSub;
        seqSub = _player.sequenceStateStream.listen((state) {
          _previewTimer?.cancel();
          if (state?.currentSource != null && _player.playing) {
            _previewTimer = Timer(Duration(seconds: durationInSeconds), () {
              if (_player.hasNext) {
                _player.seekToNext();
              } else {
                _player.stop();
              }
            });
          }
        });
        
        // Vẫn phải chặn (await) lại để màn hình UI không bị tắt sớm
        await _player.playerStateStream.firstWhere(
          (state) => state.processingState == ProcessingState.completed || 
                     state.processingState == ProcessingState.idle || 
                     _isCancelRequested
        );
        seqSub.cancel();
      }
    } finally {
      await _configureSessionUsage(AndroidAudioUsage.media);
    }
  }
}
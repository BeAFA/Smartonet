import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:logging/logging.dart';
import 'dart:io';

class AudioService {
  static final _log = Logger('AudioService');
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;

  AudioService._internal();

  final AudioPlayer _player = AudioPlayer();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    
    // Cấu hình Session để không bị xung đột với các app khác
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.alarm,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
    ));
    _initialized = true;
  }

  // Hàm nghe thử nhạc (Preview) khi chọn trong cài đặt
  Future<void> playPreview({
    required String source,
  }) async {
    await init();
    
    // Reset player để tránh lỗi state
    if (_player.playing) {
      await _player.stop();
    }

    try {
      // Kiểm tra xem source là đường dẫn file hay asset
      // Logic: Nếu đường dẫn chứa '/', khả năng cao là file hệ thống. 
      // Assets thường chỉ là 'assets/...'
      bool isFile = source.startsWith('/') || source.contains(Platform.pathSeparator);
      
      // Kiểm tra kỹ hơn nếu là file
      if (isFile) {
         if (await File(source).exists()) {
            await _player.setFilePath(source);
         } else {
            // Fallback nếu file lỗi -> Chạy nhạc mặc định
            await _player.setAsset('assets/Default/alarm_digital.wav');
         }
      } else {
        // Nếu là asset
        await _player.setAsset(source);
      }

      await _player.setVolume(1.0);
      await _player.setLoopMode(LoopMode.off); // Nghe thử thì không cần lặp
      await _player.play();
    } catch (e) {
      _log.warning("Lỗi phát nhạc preview: $e");
    }
  }

  // Dùng hàm này để tắt nhạc nghe thử
  Future<void> stopPreview() async {
    if (_player.playing) {
      await _player.stop();
    }
  }

  void dispose() {
    _player.dispose();
  }

  Future<String?> pickAudioFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg'],
    );
    if (result != null) {
      return result.files.single.path;
    }
    return null;
  }
}
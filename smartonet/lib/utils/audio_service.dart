import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;

  AudioService._internal();

  final AudioPlayer _player = AudioPlayer();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.sonification,
          usage: AndroidAudioUsage.alarm,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ),
    );
    _initialized = true;
  }

  Future<void> playAlarm({
    required String source,
    bool isAsset = true,
    double volume = 1.0,
    bool loop = true,
  }) async {
    await init();

    await _player.setLoopMode(loop ? LoopMode.one : LoopMode.off);
    await _player.setVolume(volume);

    if (isAsset) {
      await _player.setAsset(source);
    } else {
      await _player.setFilePath(source);
    }

    await _player.play();
  }

  Future<void> stopAlarm() async {
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
      allowedExtensions: ['mp3', 'wav', 'm4a', 'aac'],
    );
    if (result != null) {
      return result.files.single.path;
    }
    return null;
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'voice_service.dart';
import 'gemini_live_service.dart';
import 'audio_player_service.dart';

enum VoiceState { idle, listening, thinking, speaking }

class VoiceChatService extends ChangeNotifier {
  final VoiceService voiceService;
  final GeminiLiveService geminiService;
  final AudioPlayerService audioService;

  VoiceState _state = VoiceState.idle;
  VoiceState get state => _state;

  StreamSubscription? _micSub;
  StreamSubscription? _geminiSub;

  bool _userStartedSpeaking = false;
  Timer? _silenceTimer;
  final double _volumeThreshold = 1200;

  VoiceChatService({
    required this.voiceService,
    required this.geminiService,
    required this.audioService,
  });

  /// START CHAT
  Future<void> start(String apiKey) async {
    await audioService.init();
    await geminiService.connect();

    /// listen AI audio
    _geminiSub = geminiService.audioStream.listen((chunk) async {
      if (_state != VoiceState.speaking) {
        _setState(VoiceState.speaking);
      }

      if (_state == VoiceState.speaking) {
        await audioService.addAudio(chunk);
      }
    });

    /// AI finished
    geminiService.onAudioComplete.listen((_) async {
      await onAiFinished();
    });

    /// Bắt đầu vòng lặp nghe
    await _startListeningLoop();
  }

  /// Bắt đầu nghe mic
  Future<void> _startListeningLoop() async {
    await voiceService.startRecording();
    _setState(VoiceState.listening);
    _userStartedSpeaking = false;
    _micSub?.cancel();
    
    // Lắng nghe stream từ mic
    _micSub = voiceService.audioStream.listen(_processMicChunk);
  }

  /// Xử lý mic chunk
  void _processMicChunk(Uint8List chunk) {
    double volume = _calculateVolume(chunk);

    if (_userStartedSpeaking && _state == VoiceState.listening) {
       geminiService.sendAudio(chunk); 
    }

    if (volume > _volumeThreshold) {
      if (!_userStartedSpeaking) {
        _userStartedSpeaking = true;
        debugPrint("🗣️ User started speaking");
      }

      // Hủy timer cũ (vì user vẫn đang nói)
      _silenceTimer?.cancel();

      // Đặt timer mới: Nếu 1.2s tiếp theo không có tiếng động lớn -> coi như nói xong
      _silenceTimer = Timer(
        const Duration(milliseconds: 1200),
        _onUserStopSpeaking,
      );
    }
  }

  /// User dừng nói (kích hoạt bởi Silence Timer)
  Future<void> _onUserStopSpeaking() async {
    if (!_userStartedSpeaking) return;

    debugPrint("🤫 User stopped speaking");
    _userStartedSpeaking = false;

    // Dừng thu âm để nhường mic cho việc khác (hoặc để tiết kiệm pin)
    await voiceService.stopRecording();
    await _micSub?.cancel();

    _setState(VoiceState.thinking);

    geminiService.sendTurnComplete(); 
  }

  /// AI nói xong
  Future<void> onAiFinished() async {
    /// dừng player
    await audioService.stop();

    /// chuyển state về idle tạm thời
    _setState(VoiceState.idle);

    /// bắt đầu turn mới (Mở mic lại để user có thể nói tiếp)
    await _startListeningLoop();
  }

  /// Tính volume để phát hiện giọng nói
  double _calculateVolume(Uint8List pcm) {
    double sum = 0;
    int count = 0;

    for (int i = 0; i < pcm.length - 1; i += 2) {
      int sample = (pcm[i + 1] << 8) | pcm[i];
      if (sample >= 32768) sample -= 65536;
      sum += sample.abs();
      count++;
    }

    return count == 0 ? 0 : sum / count;
  }

  /// Stop toàn bộ
  Future<void> stop() async {
    _silenceTimer?.cancel();

    try {
      await voiceService.stopRecording();
    } catch (_) {}

    await audioService.stop();

    await _micSub?.cancel();
    await _geminiSub?.cancel();

    await geminiService.disconnect();

    _setState(VoiceState.idle);
  }

  void _setState(VoiceState s) {
    if (_state == s) return;
    _state = s;
    notifyListeners();
  }

  void disposeAll() {
    stop();
    // Giả sử các service này có hàm dispose()
    voiceService.dispose(); 
    audioService.dispose();
    geminiService.dispose();
  }
}
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

  // --- 1. Cấu hình VAD (Voice Activity Detection) ---
  final double _volumeThreshold = 1500.0; // Ngưỡng âm lượng phát hiện giọng nói
  Timer? _silenceTimer;
  bool _isUserSpeaking = false;

  VoiceChatService({
    required this.voiceService,
    required this.geminiService,
    required this.audioService,
  });

  Future<void> start(String apiKey) async {
    await audioService.init();
    await geminiService.connect(apiKey);

    await _geminiSub?.cancel();
    _geminiSub = geminiService.audioStream.listen((audio) {
      // Khi có luồng âm thanh trả về -> AI đang nói
      _setState(VoiceState.speaking);
      audioService.addAudio(audio);
    });

    await voiceService.startRecording();
    _setState(VoiceState.listening);
    _isUserSpeaking = false;

    await _micSub?.cancel();
    _micSub = voiceService.audioStream?.listen((chunk) {
      _processAudioChunk(chunk);
    });
  }

  // --- 2. Xử lý luồng âm thanh, Turn State và Ngắt lời (Barge-in) ---
  void _processAudioChunk(Uint8List chunk) {
    // Luôn đẩy audio lên server, Gemini sẽ tự động hiểu ngữ cảnh
    geminiService.sendAudio(chunk);

    double volume = _calculateVolume(chunk);

    if (volume > _volumeThreshold) {
      // User BẮT ĐẦU NÓI
      if (!_isUserSpeaking) {
        _isUserSpeaking = true;
        debugPrint("VAD: Phát hiện giọng nói.");

        // Nếu AI đang nói mà user cất tiếng -> Ngắt lời ngay lập tức
        if (_state == VoiceState.speaking) {
          debugPrint("VAD: Ngắt lời AI (Barge-in)...");
          audioService.stop();
          geminiService.interruptAI();
          _setState(VoiceState.listening);
        }
      }

      // Hủy timer đếm ngược khoảng lặng cũ
      _silenceTimer?.cancel();
      
      // Bắt đầu đếm ngược lại. Nếu sau 1200ms không có tiếng ồn -> User DỪNG NÓI
      _silenceTimer = Timer(const Duration(milliseconds: 1200), () {
        _isUserSpeaking = false;
        debugPrint("VAD: Khoảng lặng (Silence Timeout). User đã nói xong.");

        // Chuyển sang trạng thái "Đang xử lý" để UI cập nhật, chờ AI trả lời
        if (_state == VoiceState.listening) {
          _setState(VoiceState.thinking);
        }
      });
    }
  }

  // Hàm tính toán âm lượng cơ bản từ dữ liệu PCM 16-bit
  double _calculateVolume(Uint8List pcmBytes) {
    if (pcmBytes.isEmpty) return 0.0;
    double sum = 0;
    int count = 0;
    for (int i = 0; i < pcmBytes.length - 1; i += 2) {
      int sample = (pcmBytes[i + 1] << 8) | pcmBytes[i];
      if (sample >= 32768) sample -= 65536;
      sum += sample.abs();
      count++;
    }
    return count == 0 ? 0.0 : sum / count;
  }

  // Vẫn giữ lại hàm interrupt thủ công cho nút bấm (nếu cần dùng)
  void interrupt() {
    if (_state == VoiceState.speaking || _state == VoiceState.thinking) {
      audioService.stop();
      geminiService.interruptAI();
      _setState(VoiceState.listening);
    }
  }

  Future<void> stop() async {
    _silenceTimer?.cancel();
    await voiceService.stopRecording();
    await audioService.stop();
    await _micSub?.cancel();
    await _geminiSub?.cancel();
    geminiService.disconnect();
    _setState(VoiceState.idle);
  }

  void _setState(VoiceState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }

  void disposeAll() {
    stop();
    voiceService.dispose();
    audioService.dispose();
    geminiService.dispose();
  }
}
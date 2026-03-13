import 'dart:async';
import 'package:flutter/foundation.dart';

import 'voice_service.dart';
import 'gemini_live_service.dart';
import 'audio_player_service.dart';

enum VoiceState {
  idle,
  listening,
  thinking,
  speaking,
}

class VoiceChatService extends ChangeNotifier {

  final VoiceService voiceService;
  final GeminiLiveService geminiService;
  final AudioPlayerService audioService;

  VoiceState _state = VoiceState.idle;
  VoiceState get state => _state;

  StreamSubscription? _geminiSub;

  VoiceChatService({
    required this.voiceService,
    required this.geminiService,
    required this.audioService,
  });

  /// kết nối AI
  Future<void> start(String apiKey) async {

    await audioService.init();
    await geminiService.connect(apiKey);

    await _geminiSub?.cancel();

    _geminiSub = geminiService.audioStream.listen((audio) async {

      if (_state != VoiceState.speaking) {
        _setState(VoiceState.speaking);
      }

      await audioService.addAudio(audio);
    });

    _setState(VoiceState.idle);
  }

  /// user bắt đầu nói
  Future<void> startListening() async {

    await voiceService.startRecording();

    _setState(VoiceState.listening);
  }

  /// user nói xong
  Future<void> stopListening() async {

    final audioChunks = await voiceService.stopRecording();

    _setState(VoiceState.thinking);

    await geminiService.sendUserAudio(audioChunks);
  }

  /// khi AI phát xong
  Future<void> onAiFinished() async {

    await audioService.stop();

    _setState(VoiceState.idle);
  }

  Future<void> stop() async {

    try {
      await voiceService.stopRecording();
    } catch (_) {}

    await audioService.stop();

    await _geminiSub?.cancel();

    await geminiService.disconnect();

    _setState(VoiceState.idle);
  }

  /// user bấm stop AI
  Future<void> stopAudio() async {

    await audioService.stop();

    _setState(VoiceState.idle);
  }

  /// replay audio
  Future<void> playLastAudio() async {

    await audioService.replay();

    _setState(VoiceState.speaking);
  }

  void _setState(VoiceState s) {

    if (_state == s) return;

    _state = s;

    notifyListeners();
  }

  void disposeAll() {

    stop();

    voiceService.dispose();
    audioService.dispose();
    geminiService.dispose();
  }
}
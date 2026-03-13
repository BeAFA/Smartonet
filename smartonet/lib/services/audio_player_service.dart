import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';

class AudioPlayerService {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  bool _isStreaming = false;
  bool _disposed = false;

  final List<Uint8List> _lastAudio = [];

  Future<void> init() async {
    if (_disposed) return;

    if (!_player.isOpen()) {
      await _player.openPlayer();
    }
  }

  Future<void> _startStream() async {
    if (_disposed) return;

    if (!_player.isOpen()) {
      await init();
    }

    if (_isStreaming) return;

    _lastAudio.clear();

    await _player.startPlayerFromStream(
      codec: Codec.pcm16,
      interleaved: true,
      numChannels: 1,
      sampleRate: 24000,
      bufferSize: 4096,
    );

    _isStreaming = true;
  }

  Future<void> addAudio(Uint8List chunk) async {
    if (_disposed) return;

    if (!_isStreaming) {
      await _startStream();
    }

    final sink = _player.uint8ListSink;

    if (sink == null) return;

    try {
      sink.add(chunk);
      _lastAudio.add(chunk);
    } catch (e) {
      debugPrint("Audio write error: $e");
    }
  }

  Future<void> stop() async {
    if (_disposed) return;

    if (_isStreaming) {
      await _player.stopPlayer();
      _isStreaming = false;
    }
  }

  /// replay audio cuối
  Future<void> replay() async {
    if (_lastAudio.isEmpty) return;

    await stop();
    await _startStream();

    final sink = _player.uint8ListSink;

    if (sink != null) {
      for (final chunk in _lastAudio) {
        sink.add(chunk);
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;

    await stop();

    if (_player.isOpen()) {
      await _player.closePlayer();
    }

    _disposed = true;
  }
}

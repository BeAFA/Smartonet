import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../services/audio_service.dart';

class AudioPreviewScreen extends StatefulWidget {
  final String keyword;
  final String targetType;
  final int playCount;
  final int? durationInSeconds;

  const AudioPreviewScreen({
    super.key,
    required this.keyword,
    this.targetType = 'both',
    this.playCount = 1,
    this.durationInSeconds,
  });

  @override
  State<AudioPreviewScreen> createState() => _AudioPreviewScreenState();
}

class _AudioPreviewScreenState extends State<AudioPreviewScreen> {
  final AudioService _audioService = AudioService();

  bool _isExiting = false;

  @override
  void initState() {
    super.initState();
    _startPlaying();
  }

  Future<void> _startPlaying() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _audioService.previewAdvanced(
        keyword: widget.keyword == 'all' ? null : widget.keyword,
        targetType: widget.targetType,
        playCount: widget.playCount,
        durationInSeconds: widget.durationInSeconds,
      );

      // Nhạc dừng hẳn (hoặc hết bài) thì màn hình tự tắt
      if (mounted && !_isExiting) {
        _isExiting = true;
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _isExiting = true;
    _audioService.stopPreview();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Nền trắng
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: Colors.black87,
            size: 28,
          ),
          onPressed: () {
            _isExiting = true;
            _audioService.stopPreview();
            Navigator.pop(context);
          },
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.music_note_rounded,
                size: 150,
                color: Colors.blueAccent,
              ),
              const SizedBox(height: 50),

              // Hiển thị tên bài hát (Đọc từ thẻ Tag của just_audio)
              StreamBuilder<SequenceState?>(
                stream: _audioService.sequenceStateStream,
                builder: (context, snapshot) {
                  final currentItem = snapshot.data?.currentSource;
                  // Lấy tag làm tiêu đề. Nếu lỗi thì fallback về keyword
                  final title = (currentItem?.tag as String?) ?? widget.keyword;

                  return Column(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Smartonet Assistant",
                        style: TextStyle(color: Colors.black45, fontSize: 16),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 50),

              // Thanh thời gian tương tác
              MultiStreamBuilder(
                audioService: _audioService,
                builder: (context, position, duration, bufferedPosition) {
                  final totalDuration = duration ?? Duration.zero;
                  final currentPosition = position;

                  return Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          thumbColor: Colors.blueAccent,
                          activeTrackColor: Colors.blueAccent,
                          inactiveTrackColor: Colors.black12,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8.0,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 16.0,
                          ),
                        ),
                        child: Slider(
                          min: 0,
                          max: totalDuration.inMilliseconds.toDouble(),
                          value: currentPosition.inMilliseconds
                              .toDouble()
                              .clamp(
                                0,
                                totalDuration.inMilliseconds.toDouble(),
                              ),
                          onChanged: (value) {
                            _audioService.seek(
                              Duration(milliseconds: value.toInt()),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(currentPosition),
                              style: const TextStyle(color: Colors.black54),
                            ),
                            Text(
                              _formatDuration(totalDuration),
                              style: const TextStyle(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 60),

              // Nút điều khiển
              StreamBuilder<PlayerState>(
                stream: _audioService.playerStateStream,
                builder: (context, snapshot) {
                  final isPlaying = snapshot.data?.playing ?? false;

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        iconSize: 40,
                        icon: const Icon(
                          Icons.skip_previous_rounded,
                          color: Colors.black87,
                        ),
                        onPressed: _audioService.skipToPrevious,
                      ),
                      const SizedBox(width: 30),

                      FloatingActionButton.large(
                        heroTag: "play_pause_btn",
                        backgroundColor: Colors.blueAccent,
                        elevation: 4,
                        onPressed: () {
                          if (isPlaying) {
                            _audioService.pausePreview();
                          } else {
                            _audioService.resumePreview();
                          }
                        },
                        child: Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 56,
                        ),
                      ),
                      const SizedBox(width: 30),

                      IconButton(
                        iconSize: 40,
                        icon: const Icon(
                          Icons.skip_next_rounded,
                          color: Colors.black87,
                        ),
                        onPressed: _audioService.skipToNext,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Widget gộp để vẽ thanh Slider mượt mà
class MultiStreamBuilder extends StatelessWidget {
  final AudioService audioService;
  final Widget Function(
    BuildContext,
    Duration position,
    Duration? duration,
    Duration bufferedPosition,
  )
  builder;

  const MultiStreamBuilder({
    super.key,
    required this.audioService,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: audioService.positionStream,
      builder: (context, positionSnapshot) {
        final position = positionSnapshot.data ?? Duration.zero;
        return StreamBuilder<Duration?>(
          stream: audioService.durationStream,
          builder: (context, durationSnapshot) {
            final duration = durationSnapshot.data;
            return StreamBuilder<Duration>(
              stream: audioService.bufferedPositionStream,
              builder: (context, bufferedPositionSnapshot) {
                final bufferedPosition =
                    bufferedPositionSnapshot.data ?? Duration.zero;
                return builder(context, position, duration, bufferedPosition);
              },
            );
          },
        );
      },
    );
  }
}

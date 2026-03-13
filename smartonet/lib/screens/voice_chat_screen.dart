import 'package:flutter/material.dart';
import '../services/voice_chat_service.dart';
import '../services/voice_service.dart';
import '../services/gemini_live_service.dart';
import '../services/audio_player_service.dart';

class VoiceChatScreen extends StatefulWidget {
  const VoiceChatScreen({super.key});

  @override
  State<VoiceChatScreen> createState() => _VoiceChatScreenState();
}

class _VoiceChatScreenState extends State<VoiceChatScreen> {
  late VoiceChatService chatService;

  bool connected = false;

  @override
  void initState() {
    super.initState();

    chatService = VoiceChatService(
      voiceService: VoiceService(),
      geminiService: GeminiLiveService(),
      audioService: AudioPlayerService(),
    );
    chatService.addListener(() {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      startChat();
    });
  }

  Future<void> startChat() async {
    const apiKey = "AIzaSy...";
    await chatService.start(apiKey);
    connected = true;
    setState(() {});
  }

  Future<void> stopChat() async {
    await chatService.stop();
    connected = false;
    setState(() {});
  }

  @override
  void dispose() {
    chatService.disposeAll();
    super.dispose();
  }

  String getStatus() {
    switch (chatService.state) {
      case VoiceState.listening:
        return "Bạn đang nói...";
      case VoiceState.thinking:
        return "AI đang suy nghĩ...";
      case VoiceState.speaking:
        return "AI đang trả lời...";
      case VoiceState.idle:
        return connected ? "Sẵn sàng nói" : "Chưa kết nối";
    }
  }

  Color getColor() {
    switch (chatService.state) {
      case VoiceState.listening:
        return Colors.red;
      case VoiceState.thinking:
        return Colors.orange;
      case VoiceState.speaking:
        return Colors.purple;
      case VoiceState.idle:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Voice AI Chat"), centerTitle: true),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            /// AI AVATAR
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 180,
              height: 180,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: getColor().withValues(alpha: 0.15),
              ),
              child: Text(
                "AI",
                style: TextStyle(
                  fontSize: 80,
                  fontWeight: FontWeight.bold,
                  color: getColor(),
                ),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () async {
                if (!connected) {
                  await startChat();
                } else {
                  await stopChat();
                }
              },
              icon: Icon(connected ? Icons.link_off : Icons.link),
              label: Text(connected ? "Ngắt kết nối AI" : "Kết nối AI"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceRecordDialog extends StatefulWidget {
  const VoiceRecordDialog({super.key});

  @override
  State<VoiceRecordDialog> createState() => _VoiceRecordDialogState();
}

class _VoiceRecordDialogState extends State<VoiceRecordDialog> {
  final SpeechToText speechToText = SpeechToText();
  bool speechEnabled = false;
  bool isRecording = false;
  String status = "Chưa ghi âm";
  String lastWords = "";
  String systemLocaleId = "";

  @override
  void initState() {
    super.initState();
    initSpeech();
  }

  @override
  void dispose() {
    speechToText.stop();
    super.dispose();
  }

  void initSpeech() async {
    speechEnabled = await speechToText.initialize(
      onError: (error) {
        debugPrint("Speech error: ${error.errorMsg}");
      },
      onStatus: (status) {
        debugPrint("Speech status: $status");
      },
    );

    if (!speechEnabled) return;

    // 🔥 Lấy locale hệ thống
    final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;
    String systemLocaleIdFull =
        "${systemLocale.languageCode}_${systemLocale.countryCode}";

    debugPrint("System locale: $systemLocaleIdFull");

    // 🔥 Lấy danh sách locale speech hỗ trợ
    var locales = await speechToText.locales();

    // 🔥 Tìm locale KHỚP NHẤT
    for (var locale in locales) {
      if (locale.localeId == systemLocaleIdFull) {
        systemLocaleId = locale.localeId;
        break;
      }
    }

    // 🔥 Nếu không có exact match → fallback theo languageCode
    if (systemLocaleId.isEmpty) {
      for (var locale in locales) {
        if (locale.localeId.startsWith(systemLocale.languageCode)) {
          systemLocaleId = locale.localeId;
          break;
        }
      }
    }

    // 🔥 Nếu vẫn không có → lấy cái đầu tiên
    if (systemLocaleId.isEmpty && locales.isNotEmpty) {
      systemLocaleId = locales.first.localeId;
    }

    debugPrint("Using speech locale: $systemLocaleId");

    startListening();

    if (mounted) setState(() {});
  }

  void startListening() async {
    if (!speechEnabled) return;
    await speechToText.listen(
      onResult: onSpeechResult,
      localeId: systemLocaleId,
    );
    if (mounted) {
      setState(() {
        isRecording = true;
        status = "Đang nghe...";
      });
    }
  }

  void onSpeechResult(SpeechRecognitionResult result) {
    if (!context.mounted) return;
    setState(() {
      lastWords = result.recognizedWords;
    });
    debugPrint("Speech result: $lastWords");
  }

  void stopListening() async {
    await speechToText.stop();
    if (!mounted) return;
    setState(() {
      isRecording = false;
      status = "Đã dừng";
    });
  }

  void restartListening() async {
    await speechToText.stop();
    if (!context.mounted) return;

    setState(() {
      lastWords = "";
      isRecording = false;
      status = "Đang nghe lại...";
    });

    startListening();
  }

  void stopRecord() {
    if (!context.mounted) return;

    setState(() {
      isRecording = false;
      status = "Ghi âm hoàn tất";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Trợ lý thông minh",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 25),

            /// MICRO BUTTON
            GestureDetector(
              onTap: () {
                isRecording ? stopListening() : startListening();
              },
              child: CircleAvatar(
                radius: 35,
                backgroundColor: isRecording ? Colors.redAccent : Colors.grey,
                child: Icon(
                  isRecording ? Icons.mic : Icons.mic_off,
                  size: 36,
                  color: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 10),

            /// STATUS
            Text(status, style: const TextStyle(fontSize: 16)),

            const SizedBox(height: 10),

            Text(
              lastWords.isEmpty ? "Hãy nói gì đó..." : lastWords,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
            ),

            const SizedBox(height: 30),

            /// BUTTONS
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                /// HỦY
                TextButton(
                  onPressed: () async {
                    await speechToText.stop();
                    debugPrint("Voice recording cancelled");
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  child: const Text("Hủy"),
                ),

                /// TẠO LẠI
                TextButton(
                  onPressed: () {
                    restartListening();
                  },
                  child: const Text("Tạo lại"),
                ),

                /// XÁC NHẬN
                ElevatedButton(
                  onPressed: () {
                    stopListening();
                    Navigator.pop(context, lastWords);
                  },
                  child: const Text("Xác nhận"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

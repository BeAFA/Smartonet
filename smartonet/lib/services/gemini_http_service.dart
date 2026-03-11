import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../database/models.dart';

class GeminiHttpService {
  static Future<Map<String, dynamic>?> analyzeIntent(
    String userText, {
    List<Note>? currentData,
  }) async {
    String apiKey = 'REMOVED'; 

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=$apiKey',
    );

    final now = DateTime.now();

    String contextData = "Danh sách trống.";
    if (currentData != null && currentData.isNotEmpty) {
      contextData = currentData
          .map((n) {
            String type = n.hasAppointment ? "Lịch hẹn" : "Ghi chú";
            return "[$type] ID: ${n.id} | Tiêu đề: '${n.title}' | Nội dung: '${n.content}' | Thời gian: ${n.time.toIso8601String()}";
          })
          .join('\n');
    }

    final prompt =
        '''
Bạn là AI trợ lý ảo thông minh cho ứng dụng ghi chú và lịch hẹn Smartonet.
Thời gian hiện tại của hệ thống: ${now.toIso8601String()}.

DỮ LIỆU HIỆN CÓ CỦA NGƯỜI DÙNG:
$contextData

NHIỆM VỤ:
Phân tích yêu cầu và trả về DUY NHẤT một chuỗi JSON hợp lệ. Không sử dụng markdown.

QUY TẮC "type":
1. Yêu cầu có tính hành động -> type: "command"
2. Chỉ chào hỏi, tâm sự -> type: "conversation"

QUY TẮC XỬ LÝ HÀNH ĐỘNG ("commands"):
- Lên kế hoạch/Danh sách: TỰ ĐỘNG CHIA NHỎ thành nhiều lệnh "create".
- Cập nhật/Xóa lịch: Đối chiếu [DỮ LIỆU HIỆN CÓ] lấy "target_id".
- Xóa nhạc: Lệnh "delete_audio", xóa bài cụ thể -> "keyword": tên bài, xóa tất cả -> "keyword": "all".
- Nghe/Phát nhạc: Dùng lệnh "preview_audio". BẮT BUỘC tuân thủ:
  + "keyword": Tên bài hát. Nếu muốn nghe "tất cả" hoặc không nói rõ tên, để "all".
  + "audio_type": "custom" (nhạc tải lên), "default" (nhạc hệ thống), hoặc "both" (không nói rõ).
  + "play_count": Số lượng bài muốn nghe. Nghe "tất cả" -> -1. Không nói rõ -> 1.
  + "duration_in_seconds": NẾU người dùng nói "nghe thử" chung chung -> 10. NẾU người dùng nói số giây cụ thể (VD: 5 giây) -> 5. NẾU người dùng yêu cầu "phát", "mở bài", "nghe toàn bộ" -> null.

CẤU TRÚC ĐỐI TƯỢNG TRONG "commands":
- "action": "create" | "update" | "delete" | "preview_audio" | "stop_preview" | "delete_audio"
- "target_id": Số nguyên ID hoặc null.
- "has_appointment": true | false.
- "title": Tiêu đề (dưới 10 chữ).
- "content": Nội dung chi tiết.
- "datetime": Định dạng "YYYY-MM-DDTHH:MM:00" hoặc null.
- "volume": 1.0 hoặc 0.0.
- "keyword": "tên bài hát | all | null"
- "audio_type": "custom | default | both"
- "play_count": 1 | 3 | -1 | null
- "duration_in_seconds": 10 | 5 | null

ĐỊNH DẠNG JSON BẮT BUỘC:
{
  "type": "command hoặc conversation",
  "message": "Câu phản hồi...",
  "commands": [
    {
      "action": "preview_audio",
      "keyword": "all",
      "audio_type": "both",
      "play_count": 1,
      "duration_in_seconds": 10
    }
  ]
}

Câu của người dùng:
"$userText"
''';

    final requestBody = jsonEncode({
      "contents": [{"parts": [{"text": prompt}]}],
      "generationConfig": {"responseMimeType": "application/json"},
    });

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: requestBody,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String textResponse = data['candidates'][0]['content']['parts'][0]['text'];
        textResponse = textResponse.replaceAll('```json', '').replaceAll('```', '').trim();
        return jsonDecode(textResponse);
      }
    } catch (e) {
      debugPrint('Lỗi khi phân tích JSON từ AI: $e');
    }
    return null;
  }
}
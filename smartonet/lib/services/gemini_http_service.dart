import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'api_key_service.dart';

class GeminiHttpService {
  static Future<Map<String, dynamic>?> analyzeIntent(String userText) async {
    // 1. Lấy API Key từ Secure Storage
    final apiKey = await ApiKeyService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('Chưa có API Key');
      return null;
    }

    // 2. Cấu hình Endpoint của Gemini 1.5 Flash
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey',
    );

    final now = DateTime.now();

    // 3. Chuẩn bị Prompt Thần Thánh
    final prompt =
        '''
Bạn là AI phân tích lệnh cho ứng dụng ghi chú và lịch hẹn Smartonet.
Thời gian hiện tại của hệ thống là: ${now.toIso8601String()}.

Nhiệm vụ: Phân tích câu nói của người dùng và trả về một JSON chuẩn xác duy nhất, KHÔNG có markdown, KHÔNG có text bọc ngoài.

Các loại "action":
- "create_alarm": Nếu câu nói có yếu tố nhắc nhở, hẹn giờ, lịch trình tương lai.
- "create_note": Nếu câu nói chỉ là ghi chú thông thường, không cần hẹn giờ.

Định dạng JSON BẮT BUỘC:
{
  "action": "create_alarm" hoặc "create_note",
  "title": "Tiêu đề ngắn gọn (dưới 10 chữ)",
  "content": "Nội dung chi tiết (nếu có, không thì để rỗng)",
  "datetime": "YYYY-MM-DDTHH:MM:00" (Chỉ áp dụng cho create_alarm. Nếu chỉ nói ngày mà không có giờ, mặc định là 08:00:00. Nếu là create_note, để null)
}

Câu của người dùng: "$userText"
''';

    // 4. Đóng gói Body theo chuẩn của Google AI Studio
    final requestBody = jsonEncode({
      "contents": [
        {
          "parts": [
            {"text": prompt},
          ],
        },
      ],
      "generationConfig": {
        "responseMimeType": "application/json", // Ép server trả về JSON
      },
    });

    try {
      // 5. Bắn Request
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: requestBody,
      );

      // 6. Xử lý Kết quả
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Bóc tách text từ cây JSON của Google trả về
        final String textResponse =
            data['candidates'][0]['content']['parts'][0]['text'];

        // Parse String JSON thành Map của Dart
        return jsonDecode(textResponse);
      } else {
        debugPrint('Lỗi HTTP: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('Lỗi khi gọi API Gemini: $e');
    }

    return null;
  }
}

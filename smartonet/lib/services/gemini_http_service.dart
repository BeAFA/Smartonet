import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class GeminiHttpService {
  static Future<Map<String, dynamic>?> analyzeIntent(String userText) async {
    // 1. Lấy API Key từ Secure Storage
    // final apiKey = await ApiKeyService.getApiKey();
    // if (apiKey == null || apiKey.isEmpty) {
    //   debugPrint('Chưa có API Key');
    //   return null;
    // }
    String apiKey = 'AIzaSyBWKW5tWirlnebYbbrNXSajU_WbwsrKBLE';

    // 2. Cấu hình Endpoint của Gemini 1.5 Flash
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey',
    );

    final now = DateTime.now();

    final prompt =
        '''
Bạn là AI phân tích câu nói cho ứng dụng ghi chú và nhắc việc Smartonet.

Thời gian hiện tại của hệ thống là: ${now.toIso8601String()}.

Nhiệm vụ:
Phân tích câu nói của người dùng và trả về DUY NHẤT một JSON hợp lệ.
Không thêm markdown, không giải thích, không thêm văn bản ngoài JSON.

------------------------------------------------

QUY TẮC PHÂN LOẠI

1. create_note

Chọn "create_note" nếu câu nói KHÔNG chứa ngày hoặc giờ.

Ví dụ:
"Mua sữa"
"Ghi chú ý tưởng làm app"

Kết quả:
action = create_note
datetime = null
volume = 0

------------------------------------------------

2. create_alarm

Chọn "create_alarm" nếu câu nói có yếu tố thời gian.

Các dạng thời gian có thể xuất hiện:
- ngày mai
- hôm nay
- thứ 2, thứ 3...
- tuần sau
- ngày 25
- 25/6

TRƯỜNG HỢP A: Chỉ có NGÀY (không có giờ)

Ví dụ:
"Ngày mai mua sữa"
"Thứ 2 nộp báo cáo"

Kết quả:
datetime = ngày đó + 08:00
volume = 0 (chỉ rung)

------------------------------------------------

TRƯỜNG HỢP B: Có GIỜ cụ thể

Ví dụ giờ:
7h
8h30
14:00
9 giờ sáng
6 giờ tối

Ví dụ câu:
"Mai 7h mua sữa"
"Thứ 2 lúc 9h họp"

Kết quả:
datetime = thời gian chính xác
volume = 1 (phát âm thanh)

------------------------------------------------

QUY TẮC TITLE

- Ngắn gọn
- Dưới 10 chữ
- Tóm tắt nội dung chính

------------------------------------------------

ĐỊNH DẠNG JSON BẮT BUỘC

{
  "action": "create_alarm" hoặc "create_note",
  "title": "Tiêu đề ngắn gọn",
  "content": "Nội dung chi tiết nếu có, nếu không để rỗng",
  "datetime": "YYYY-MM-DDTHH:MM:00 hoặc null",
  "volume": 0 hoặc 1
}

Quy tắc datetime:
- create_note → datetime = null
- create_alarm → phải chuyển đổi thời gian dựa trên thời gian hệ thống

------------------------------------------------

Câu của người dùng:
"$userText"
''';

    final requestBody = jsonEncode({
      "contents": [
        {
          "parts": [
            {"text": prompt},
          ],
        },
      ],
      "generationConfig": {
        "responseMimeType": "application/json",
      },
    });

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: requestBody,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String textResponse =
            data['candidates'][0]['content']['parts'][0]['text'];

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

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiKeyService {
  static const _storage = FlutterSecureStorage();
  static const _keyName = 'REMOVED';

  // Lưu Key
  static Future<void> saveApiKey(String apiKey) async {
    await _storage.write(key: _keyName, value: apiKey.trim());
  }

  // Lấy Key ra sử dụng
  static Future<String?> getApiKey() async {
    return await _storage.read(key: _keyName);
  }

  // Xóa Key (nếu người dùng muốn đăng xuất/đổi key)
  static Future<void> deleteApiKey() async {
    await _storage.delete(key: _keyName);
  }
}
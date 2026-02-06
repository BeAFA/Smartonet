import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();

void showPermissionBanner({required VoidCallback onDismiss}) {
  messengerKey.currentState?.removeCurrentMaterialBanner();
  messengerKey.currentState?.showMaterialBanner(
    MaterialBanner(
      elevation: 2,
      backgroundColor: Color(0xFFFF5722),
      leading: const Icon(Icons.alarm_off, color: Colors.white, size: 28),
      content: const Text(
        "Cần quyền Báo thức để tiếp tục. Vui lòng cấp quyền trong Cài đặt.",
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
      ),
      actions: [
        TextButton(
          onPressed: () {
            messengerKey.currentState?.hideCurrentMaterialBanner();
            onDismiss();
          },
          child: const Text("Để sau", style: TextStyle(color: Colors.white70)),
        ),
        TextButton(
          onPressed: () {
            messengerKey.currentState?.hideCurrentMaterialBanner();
            onDismiss();
            openAppSettings();
          },
          child: const Text(
            "Mở cài đặt",
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    ),
  );
}

void showPermissionDialog(BuildContext context, {bool showPermanentDisable = false}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text("Cần cấp quyền thông báo"),
      content: const Text(
        "Bạn đã từ chối quyền này vĩnh viễn. Để báo thức hoạt động, "
        "vui lòng vào Cài đặt > Quyền > Thông báo và bật lên.",
      ),
      actions: [
        if (showPermanentDisable)
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('hide_permission_forever', true);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text("Tắt vĩnh viễn", style: TextStyle(color: Colors.red)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text("Để sau", style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            openAppSettings();
          },
          child: const Text(
            "Mở Cài đặt",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
}

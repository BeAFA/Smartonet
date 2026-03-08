import 'package:flutter/material.dart';

Future<void> showNoInternetDialog(BuildContext context) {
  return showDialog(
    context: context,
    barrierDismissible: false, // Bắt buộc người dùng phải bấm nút Đóng (tuỳ chọn)
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Lỗi kết nối'),
        content: const Text('Vui lòng kiểm tra lại kết nối Internet và thử lại.'),
        actions: <Widget>[
          TextButton(
            child: const Text('Đóng'),
            onPressed: () {
              // Lệnh này sẽ đóng Dialog, làm cho await ở trên hoàn thành
              Navigator.of(context).pop(); 
            },
          ),
        ],
      );
    },
  );
}
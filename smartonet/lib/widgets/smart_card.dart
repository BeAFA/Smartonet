import 'package:flutter/material.dart';

class SmartCard extends StatelessWidget {
  final String title;
  final String content;

  final DateTime? date;
  final DateTime? time;

  final bool isFullWidth;
  final bool isLinkedAppointment;
  final bool isPastAppointment;

  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const SmartCard({
    super.key,
    required this.title,
    required this.content,
    this.date,
    this.time,
    this.isFullWidth = false,
    this.isLinkedAppointment = false,
    this.isPastAppointment = false,
    this.onEdit,
    this.onDelete,
  });

  String _buildTimeText() {
    if (date == null || time == null) return "";

    if (isLinkedAppointment) {
      final hour = time!.hour.toString().padLeft(2, '0');
      final minute = time!.minute.toString().padLeft(2, '0');
      return "$hour:$minute • ${date!.day}/${date!.month}";
    } else {
      return "Ngày: ${date!.day}/${date!.month}";
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = _buildTimeText();

    return Card(
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [

            /// ===== HEADER =====
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [

                      /// Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isLinkedAppointment
                              ? Colors.orange.shade50
                              : Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isLinkedAppointment ? "Lịch hẹn" : "Note",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isLinkedAppointment
                                ? Colors.deepOrange
                                : Colors.blue,
                          ),
                        ),
                      ),

                      /// Past badge
                      if (isPastAppointment)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            "Đã qua",
                            style: TextStyle(fontSize: 10),
                          ),
                        ),

                      /// Time
                      if (timeStr.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 12,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 2),
                            ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxWidth: 110),
                              child: Text(
                                timeStr,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

                /// ACTION BUTTONS
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onEdit != null)
                      InkWell(
                        onTap: onEdit,
                        child: const Icon(
                          Icons.edit,
                          size: 18,
                          color: Colors.orange,
                        ),
                      ),
                    if (onDelete != null) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: onDelete,
                        child: const Icon(
                          Icons.delete,
                          size: 18,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),

            const SizedBox(height: 6),

            /// TITLE
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),

            /// CONTENT
            if (content.isNotEmpty)
              Text(
                content,
                maxLines: isFullWidth ? 5 : 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
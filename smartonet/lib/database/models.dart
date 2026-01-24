class Note {
  int? id;
  String title;
  String content;
  DateTime date;
  DateTime time;
  bool hasAppointment;

  Note({
    this.id,
    required this.title,
    required this.content,
    required this.date,
    required this.time,
    this.hasAppointment = true,
  }) {
    time = DateTime(
      time.year,
      time.month,
      time.day,
      time.hour,
      time.minute,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'date': date.toIso8601String(),
      'time': time.toIso8601String(),
      'has_appointment': hasAppointment ? 1 : 0,
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'],
      title: map['title'],
      content: map['content'],
      date: DateTime.parse(map['date']),
      time: DateTime.parse(map['time']),
      hasAppointment: map['has_appointment'] == 1,
    );
  }
}

class Note {
  int? id;
  String title;
  String content;
  DateTime date;
  DateTime time;
  bool hasAppointment;
  String? alarmAudioPath;
  double volume;

  Note({
    this.id,
    required this.title,
    required this.content,
    required this.date,
    required this.time,
    this.hasAppointment = true,
    this.alarmAudioPath,
    this.volume = 1.0,
  }) {
    time = DateTime(time.year, time.month, time.day, time.hour, time.minute);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'date': date.toIso8601String(),
      'time': time.toIso8601String(),
      'has_appointment': hasAppointment ? 1 : 0,
      'alarm_audio_path': alarmAudioPath,
      'volume': volume,
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
      alarmAudioPath: map['alarm_audio_path'],
      volume: map['volume'] != null ? (map['volume'] as num).toDouble() : 1.0,
    );
  }

  bool get isPastAppointment {
    if (!hasAppointment) return false;
    return time.isBefore(DateTime.now());
  }

  DateTime get dateOnly => DateTime(time.year, time.month, time.day);
}

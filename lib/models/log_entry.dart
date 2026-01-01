
class LogEntry {
  final int? id;
  final String username;
  final String action;
  final String details;
  final DateTime timestamp;

  LogEntry({
    this.id,
    required this.username,
    required this.action,
    required this.details,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'action': action,
      'details': details,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory LogEntry.fromMap(Map<String, dynamic> map) {
    return LogEntry(
      id: map['id'],
      username: map['username'],
      action: map['action'],
      details: map['details'],
      timestamp: DateTime.parse(map['timestamp']),
    );
  }
}

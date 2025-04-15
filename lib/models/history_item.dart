class HistoryItem {
  final String path;
  final String timestamp;
  final String explanation;

  HistoryItem({
    required this.path,
    required this.timestamp,
    required this.explanation,
  });

  // Convert to and from JSON for persistence
  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      path: json['path'] as String,
      timestamp: json['timestamp'] as String,
      explanation: json['explanation'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'timestamp': timestamp,
      'explanation': explanation,
    };
  }
}
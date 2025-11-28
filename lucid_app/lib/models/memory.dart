/// Represents a saved visual memory
class Memory {
  final String id;
  final String imagePath;
  final String userLabel; // e.g., "headache medication"
  final String visionDescription; // e.g., "white bottle with blue cap"
  final DateTime timestamp;
  final int ragDocumentId;
  final double? lastMatchScore;

  // Location metadata
  final double? latitude;
  final double? longitude;
  final String? locationName; // e.g., "Building 7, MIT Campus"

  Memory({
    required this.id,
    required this.imagePath,
    required this.userLabel,
    required this.visionDescription,
    required this.timestamp,
    required this.ragDocumentId,
    this.lastMatchScore,
    this.latitude,
    this.longitude,
    this.locationName,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'imagePath': imagePath,
        'userLabel': userLabel,
        'visionDescription': visionDescription,
        'timestamp': timestamp.toIso8601String(),
        'ragDocumentId': ragDocumentId,
        'lastMatchScore': lastMatchScore,
        'latitude': latitude,
        'longitude': longitude,
        'locationName': locationName,
      };

  factory Memory.fromJson(Map<String, dynamic> json) => Memory(
        id: json['id'],
        imagePath: json['imagePath'],
        userLabel: json['userLabel'],
        visionDescription: json['visionDescription'],
        timestamp: DateTime.parse(json['timestamp']),
        ragDocumentId: json['ragDocumentId'],
        lastMatchScore: json['lastMatchScore'],
        latitude: json['latitude'],
        longitude: json['longitude'],
        locationName: json['locationName'],
      );

  String get combinedContent => '$userLabel: $visionDescription';

  double get confidencePercentage => lastMatchScore != null
      ? ((1 - lastMatchScore!) * 100).clamp(0, 100)
      : 0;
}

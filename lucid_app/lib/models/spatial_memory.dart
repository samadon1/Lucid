import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart' as vm;

/// Represents a spatial memory of an object in 3D space using ARKit
class SpatialMemory {
  final String label; // User-given label (e.g., "keys", "laptop")
  final String anchorId; // ARKit anchor identifier
  final vm.Vector3 position; // 3D position in world space (x, y, z)
  final DateTime timestamp; // When the memory was created

  SpatialMemory({
    required this.label,
    required this.anchorId,
    required this.position,
    required this.timestamp,
  });

  /// Calculate distance from a given position to this object
  double distanceFrom(vm.Vector3 currentPosition) {
    return (position - currentPosition).length;
  }

  /// Get relative direction description (e.g., "to your left", "behind you")
  String getRelativeDirection(vm.Vector3 currentPosition, vm.Vector3 currentForward) {
    final toObject = position - currentPosition;
    final toObjectNormalized = toObject.normalized();

    // Calculate angle between forward direction and object direction
    final dotProduct = currentForward.dot(toObjectNormalized);
    final angle = vm.degrees(math.acos(dotProduct.clamp(-1.0, 1.0)));

    // Calculate cross product to determine left/right
    final cross = currentForward.cross(toObjectNormalized);
    final isLeft = cross.y > 0;

    // Determine direction based on angle
    if (angle < 30) {
      return 'ahead';
    } else if (angle > 150) {
      return 'behind you';
    } else if (angle < 90) {
      return isLeft ? 'to your left ahead' : 'to your right ahead';
    } else {
      return isLeft ? 'to your left' : 'to your right';
    }
  }

  /// Convert to JSON for storage (if needed later)
  Map<String, dynamic> toJson() => {
        'label': label,
        'anchorId': anchorId,
        'position': {
          'x': position.x,
          'y': position.y,
          'z': position.z,
        },
        'timestamp': timestamp.toIso8601String(),
      };

  /// Create from JSON
  factory SpatialMemory.fromJson(Map<String, dynamic> json) => SpatialMemory(
        label: json['label'],
        anchorId: json['anchorId'],
        position: vm.Vector3(
          json['position']['x'],
          json['position']['y'],
          json['position']['z'],
        ),
        timestamp: DateTime.parse(json['timestamp']),
      );
}

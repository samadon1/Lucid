import 'package:flutter/material.dart';

class FaceMemory {
  final String id;
  final List<double> descriptor;
  final String imageFilePath;
  final Rect boundingBox;
  final DateTime timestamp;
  String? name;
  String? notes;

  FaceMemory({
    required this.id,
    required this.descriptor,
    required this.imageFilePath,
    required this.boundingBox,
    required this.timestamp,
    this.name,
    this.notes,
  });
}

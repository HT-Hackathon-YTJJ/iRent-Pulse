import 'dart:ui' show Rect;

/// One thing the detector found, in **upright, normalised** frame coordinates
/// (0–1 on both axes, y down) so the caller never has to know how the sensor
/// was mounted.
class Detection {
  const Detection({required this.box, required this.score, required this.label});

  final Rect box;
  final double score;
  final String label;

  double get area => box.width * box.height;
}

/// 車牌比對 — the 「這是不是你租的那台車」 half of L0.
///
/// The OCR itself lives in [plate_reader.dart]; everything here is pure Dart so
/// the matching rules can be tested without a camera, which matters because the
/// rules are where this check is easy to get wrong in the expensive direction.
///
/// **Which way this is allowed to be wrong.** Saying "this is not your car"
/// about the right car is far worse than staying quiet about the wrong one: the
/// driver is standing at the correct vehicle being told to go away, and there
/// is nothing they can do to argue. Every decision below therefore leans
/// towards [PlateMatch.unknown] — no reading, an unreadable reading, or a
/// single frame's disagreement all mean "say nothing", and only a plate that is
/// read clearly and repeatedly as *something else* turns the frame red.
library;

import 'dart:math' as math;

/// What L0 currently believes about the plate in frame.
enum PlateMatch {
  /// No plate read, or not enough agreement to say anything. Renders exactly
  /// as the check did before it existed.
  unknown,

  /// A plate matching the rented car was read.
  match,

  /// A plate was read clearly, repeatedly, and it is not this car.
  mismatch,
}

/// Glyph pairs OCR confuses on a plate, folded onto one canonical character.
///
/// Plates are photographed at an angle, at distance, often in shadow, and the
/// typeface is the one thing every reader trips on the same way. Folding both
/// sides of the comparison means `RDS-6583` still matches a frame that came
/// back `RD5-65B3`, which is the difference between a check that works in a car
/// park and one that only works on a flat scan.
const Map<String, String> _confusions = {
  'O': '0',
  'Q': '0',
  'I': '1',
  'L': '1',
  'S': '5',
  'Z': '2',
  'B': '8',
  'G': '6',
};

/// Uppercase, strip separators, fold the confusable glyphs.
///
/// Both the expected plate and every candidate go through this, so the
/// comparison is between two strings in the same reduced alphabet.
String normalisePlate(String raw) {
  final buffer = StringBuffer();
  for (final ch in raw.toUpperCase().split('')) {
    if (!RegExp(r'[A-Z0-9]').hasMatch(ch)) continue;
    buffer.write(_confusions[ch] ?? ch);
  }
  return buffer.toString();
}

/// Characters that appear *between* the two halves of a plate.
final RegExp _separators = RegExp(r'[-–—·・.]');

/// Splits OCR text into runs of plate characters, keeping separators inside a
/// run so `RDS-6583` survives as one piece.
final RegExp _gaps = RegExp(r'[^A-Z0-9\-–—·・.]+');

/// Every plate-shaped token in a block of OCR text, normalised.
///
/// A car carries plenty of other text — model badges, dealer stickers, the
/// windscreen permit — and this is the filter that keeps it out.
///
/// **The filtering has to happen before the glyph folding, not after.** Folding
/// maps letters *onto* digits (O→0, L→1), so `COROLLA` comes out of
/// [normalisePlate] as `C0R011A` — full of digits, and indistinguishable from a
/// plate by any test applied downstream of it. Asking "did the OCR actually
/// read a digit" is only a real question while the raw characters are still
/// raw.
///
/// A plate is then anything that has **both** a letter and a digit in it and is
/// 5–8 characters long. Every current Taiwanese format satisfies that
/// (`AB-1234`, `ABC-1234`, `1234-AB`) and almost nothing else on a car does.
List<String> extractPlates(String ocrText) {
  final chunks = ocrText
      .toUpperCase()
      .split(_gaps)
      .where((chunk) => chunk.isNotEmpty)
      .toList();

  final found = <String>[];

  void consider(String raw) {
    final stripped = raw.replaceAll(_separators, '');
    if (stripped.length < 5 || stripped.length > 8) return;
    if (!RegExp(r'[0-9]').hasMatch(stripped)) return;
    if (!RegExp(r'[A-Z]').hasMatch(stripped)) return;
    final token = normalisePlate(stripped);
    if (!found.contains(token)) found.add(token);
  }

  for (var i = 0; i < chunks.length; i++) {
    consider(chunks[i]);
    // ML Kit often reports the two halves of a plate as separate words when the
    // dash is a bolt hole or a plate frame — `RDS 6583` rather than `RDS-6583`.
    // Neither half is a plate on its own, so adjacent pairs get a look too.
    if (i + 1 < chunks.length) consider(chunks[i] + chunks[i + 1]);
  }
  return found;
}

/// Levenshtein distance, capped at [limit] so a long mismatch exits early.
int _distance(String a, String b, {int limit = 2}) {
  if ((a.length - b.length).abs() > limit) return limit + 1;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0);
    current[0] = i;
    var best = current[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      current[j] = math.min(
        math.min(current[j - 1] + 1, previous[j] + 1),
        previous[j - 1] + cost,
      );
      best = math.min(best, current[j]);
    }
    if (best > limit) return limit + 1;
    previous = current;
  }
  return previous[b.length];
}

/// One reading against the rented car's plate.
///
/// Seeing the right plate anywhere in the frame is proof this is the right car,
/// so a match on *any* candidate wins. Only when there are readable candidates
/// and none of them is this car does the reading count as a mismatch.
PlateMatch matchPlates(List<String> candidates, String expected) {
  final target = normalisePlate(expected);
  if (target.isEmpty || candidates.isEmpty) return PlateMatch.unknown;

  for (final candidate in candidates) {
    // One substitution of forgiveness on top of the glyph folding. A plate read
    // at 15 metres in the rain loses a character; a different car does not
    // differ from this one by one character.
    if (_distance(candidate, target) <= 1) return PlateMatch.match;
  }
  return PlateMatch.mismatch;
}

/// Turns a stream of noisy per-frame readings into something the viewfinder can
/// show without strobing.
///
/// The asymmetry is the point, and it is the same asymmetry as everywhere else
/// in L0: a match is believed immediately and remembered, a mismatch has to be
/// argued for across several frames before it is allowed to turn the frame red.
class PlateWatcher {
  PlateWatcher({required this.expected});

  /// The plate on the rental agreement, e.g. `RDS-6583`.
  final String expected;

  /// Consecutive mismatched readings before the frame turns red.
  ///
  /// Three at the reader's ~1.5 Hz is about two seconds of the phone being
  /// pointed at a plate that is consistently not this car — long enough that a
  /// single bad frame, a passing car or half a plate at the edge cannot do it.
  static const int mismatchStreak = 3;

  /// How long a confirmed match keeps the check quiet after the plate leaves
  /// the frame.
  ///
  /// The driver reads the plate once and then walks around the car to shoot the
  /// other three corners, where there is no plate to see. Without this the
  /// check would forget and start arguing with them at the second corner.
  static const Duration matchHolds = Duration(minutes: 2);

  PlateMatch _state = PlateMatch.unknown;

  /// How many readings each non-matching plate has appeared in.
  ///
  /// Counting **per plate** rather than counting readings is what makes the
  /// check survive a text-rich scene. On the bench the camera caught a screen
  /// full of prose and one reading produced eleven plate-shaped candidates —
  /// `5105PN6`, `493RNET`, `21MA6E` — none of them a plate and none of them the
  /// same twice. A streak that counted *readings* would have turned the frame
  /// red on three frames of that. A car that genuinely is not this one reads as
  /// the same string every time, so it still crosses [mismatchStreak] in about
  /// two seconds.
  final Map<String, int> _wrongSeen = {};

  DateTime? _matchedAt;

  /// The last plate that was read but did not belong to this car, for the copy
  /// that has to name it.
  String? lastSeen;

  PlateMatch get state {
    if (_state == PlateMatch.match &&
        _matchedAt != null &&
        DateTime.now().difference(_matchedAt!) > matchHolds) {
      return PlateMatch.unknown;
    }
    return _state;
  }

  /// Feed one OCR result in. Null (or empty) means the reader did not run or
  /// found nothing — which is not evidence of anything and leaves the state be.
  void observe(String? ocrText) {
    if (ocrText == null || ocrText.trim().isEmpty) return;
    final candidates = extractPlates(ocrText);
    if (candidates.isEmpty) return;

    switch (matchPlates(candidates, expected)) {
      case PlateMatch.match:
        _wrongSeen.clear();
        _matchedAt = DateTime.now();
        _state = PlateMatch.match;
        lastSeen = null;
      case PlateMatch.mismatch:
        // A confirmed match is not overturned by a stray reading: at the corner
        // shots the driver's own car and the one parked next to it are both in
        // frame, and the neighbour's plate is often the more legible of the two.
        if (state == PlateMatch.match) return;
        for (final candidate in candidates) {
          final seen = (_wrongSeen[candidate] ?? 0) + 1;
          _wrongSeen[candidate] = seen;
          if (seen >= mismatchStreak) {
            lastSeen = candidate;
            _state = PlateMatch.mismatch;
          }
        }
      case PlateMatch.unknown:
        break;
    }
  }

  /// Between slots and after a 重拍. The confirmed-match memory deliberately
  /// survives — it is about the car, not about the shot.
  void restart() {
    _wrongSeen.clear();
    if (_state == PlateMatch.mismatch) _state = PlateMatch.unknown;
  }
}

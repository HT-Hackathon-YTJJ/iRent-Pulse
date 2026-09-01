import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A rental that is still running, restored from disk.
@immutable
class ActiveTrip {
  const ActiveTrip({
    required this.plate,
    required this.stage,
    required this.sheetSize,
  });

  /// Number plate of the car that was unlocked. The demo has one vehicle
  /// profile, so the plate is the whole of its identity.
  final String plate;

  /// [TripStage] by name. Stored as a string rather than an index so that
  /// adding a stage later cannot silently re-point an old save at a new one.
  final String stage;

  /// Where the 車輛資訊 sheet was left, as a fraction of the viewport.
  final double sheetSize;

  @override
  bool operator ==(Object other) =>
      other is ActiveTrip &&
      other.plate == plate &&
      other.stage == stage &&
      other.sheetSize == sheetSize;

  @override
  int get hashCode => Object.hash(plate, stage, sheetSize);
}

/// The one piece of state in this app that has to survive the process dying.
///
/// Everything else — which pin is selected, how far the booking sheet is
/// pulled up — is a view state that is fine to lose, because losing it costs
/// the user a tap. A rental is not like that: the car is moving, it is being
/// billed by the minute, and the return is gated behind this screen. Coming
/// back to a map with no sign of the trip reads as "the app lost my rental",
/// which is the worst thing a rental app can say. So the trip, its stage and
/// the height the driver left the sheet at are written to disk and put back
/// exactly as they were.
///
/// Writes happen when something settles — the sheet is let go, the stage is
/// switched, the return completes — never per frame.
abstract final class TripStore {
  static const _kPlate = 'trip.plate';
  static const _kStage = 'trip.stage';
  static const _kSheet = 'trip.sheet';

  /// In-memory mirror, so a restore never has to wait on the platform channel
  /// twice and a widget test can run without one.
  static ActiveTrip? _cached;

  static ActiveTrip? get cached => _cached;

  static Future<SharedPreferences>? _prefs;

  static Future<SharedPreferences> _open() =>
      _prefs ??= SharedPreferences.getInstance();

  /// Reads the stored trip, or null if the last one was returned.
  ///
  /// Storage failures are swallowed: a demo that cannot reach its preferences
  /// should open on the map, not on a crash screen.
  static Future<ActiveTrip?> load() async {
    try {
      final prefs = await _open();
      final plate = prefs.getString(_kPlate);
      if (plate == null || plate.isEmpty) return _cached = null;
      return _cached = ActiveTrip(
        plate: plate,
        stage: prefs.getString(_kStage) ?? '',
        sheetSize: prefs.getDouble(_kSheet) ?? 0,
      );
    } catch (error) {
      debugPrint('TripStore: 無法讀取租用狀態 — $error');
      return _cached = null;
    }
  }

  static Future<void> start({
    required String plate,
    required String stage,
    required double sheetSize,
  }) async {
    _cached = ActiveTrip(plate: plate, stage: stage, sheetSize: sheetSize);
    await _write((prefs) async {
      await prefs.setString(_kPlate, plate);
      await prefs.setString(_kStage, stage);
      await prefs.setDouble(_kSheet, sheetSize);
    });
  }

  static Future<void> saveStage(String stage) async {
    final trip = _cached;
    if (trip == null) return;
    _cached = ActiveTrip(
      plate: trip.plate,
      stage: stage,
      sheetSize: trip.sheetSize,
    );
    await _write((prefs) => prefs.setString(_kStage, stage));
  }

  static Future<void> saveSheet(double size) async {
    final trip = _cached;
    if (trip == null || (trip.sheetSize - size).abs() < 0.005) return;
    _cached = ActiveTrip(
      plate: trip.plate,
      stage: trip.stage,
      sheetSize: size,
    );
    await _write((prefs) => prefs.setDouble(_kSheet, size));
  }

  /// The car is back. Nothing about this trip should survive.
  static Future<void> end() async {
    _cached = null;
    await _write((prefs) async {
      await prefs.remove(_kPlate);
      await prefs.remove(_kStage);
      await prefs.remove(_kSheet);
    });
  }

  static Future<void> _write(
    Future<void> Function(SharedPreferences prefs) body,
  ) async {
    try {
      await body(await _open());
    } catch (error) {
      debugPrint('TripStore: 無法寫入租用狀態 — $error');
    }
  }
}

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Switches for running the demo on a show floor, kept across restarts.
///
/// Only one so far: 車牌比對. At an event the car on the floor is rarely the
/// one on the rental agreement, so every corner shot came back 車輛不符 and
/// could only be filed through 仍要送出. Turning the comparison off is a tap
/// in the viewfinder, and it stays off until it is turned back on, so the
/// person giving the demo sets it once rather than before every run.
abstract final class DemoSwitches {
  static const _kPlateCheck = 'demo.plate_check';

  /// Whether a plate read as another car's holds the corner shots back.
  static final ValueNotifier<bool> plateCheck = ValueNotifier(true);

  static Future<SharedPreferences>? _prefs;

  static Future<SharedPreferences> _open() =>
      _prefs ??= SharedPreferences.getInstance();

  /// Storage failures leave the defaults: the check on.
  static Future<void> load() async {
    try {
      final prefs = await _open();
      plateCheck.value = prefs.getBool(_kPlateCheck) ?? true;
    } catch (error) {
      debugPrint('DemoSwitches: 無法讀取設定 — $error');
    }
  }

  static Future<void> setPlateCheck(bool on) async {
    plateCheck.value = on;
    try {
      final prefs = await _open();
      await prefs.setBool(_kPlateCheck, on);
    } catch (error) {
      debugPrint('DemoSwitches: 無法儲存設定 — $error');
    }
  }
}

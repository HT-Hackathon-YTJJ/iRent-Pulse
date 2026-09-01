import 'package:flutter_test/flutter_test.dart';
import 'package:irent_pulse/services/trip_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A rental has to survive the app being killed.
///
/// The failure this guards against is not subtle: come back to the map with no
/// sign of the trip and the app has told the user it lost their rental, while
/// the car is still unlocked and still being billed.
void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await TripStore.end();
  });

  test('nothing is stored before a car is unlocked', () async {
    expect(await TripStore.load(), isNull);
  });

  test('a running rental comes back with its stage and its sheet height', () async {
    await TripStore.start(plate: 'RDS-6583', stage: 'driving', sheetSize: 0.45);

    final restored = await TripStore.load();
    expect(restored, isNotNull);
    expect(restored!.plate, 'RDS-6583');
    expect(restored.stage, 'driving');
    expect(restored.sheetSize, 0.45);
  });

  test('the sheet height follows the last place it settled', () async {
    await TripStore.start(plate: 'RDS-6583', stage: 'driving', sheetSize: 0.74);
    await TripStore.saveSheet(0.96);
    expect((await TripStore.load())!.sheetSize, 0.96);
  });

  test('a stage switch survives on its own', () async {
    await TripStore.start(plate: 'RDS-6583', stage: 'departure', sheetSize: 0.74);
    await TripStore.saveStage('lowFuel');

    final restored = await TripStore.load();
    expect(restored!.stage, 'lowFuel');
    expect(restored.sheetSize, 0.74, reason: '換情境不該動到 Sheet 高度');
  });

  test('finishing the return leaves nothing behind', () async {
    await TripStore.start(plate: 'RDS-6583', stage: 'driving', sheetSize: 0.74);
    await TripStore.end();

    expect(await TripStore.load(), isNull);
    // And a write after the end is a no-op rather than a resurrection: the
    // status sheet's dispose and the lifecycle observer both fire after the
    // flow has already cleared the trip.
    await TripStore.saveSheet(0.9);
    await TripStore.saveStage('driving');
    expect(await TripStore.load(), isNull);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:irent_pulse/data/return_inspection.dart';
import 'package:irent_pulse/l0/capture_session.dart';
import 'package:irent_pulse/services/inspection_api.dart';
import 'package:irent_pulse/services/return_session.dart';

/// The shape L1 actually returns, minus the fields the driver-facing screens
/// never read.
Map<String, Object?> l1Json({
  required String slot,
  bool assessable = true,
  String? reason,
  bool retake = false,
  String? hint,
  String? cleanliness,
  List<String> items = const [],
  String? error,
}) => {
  'photo_id': 'p_$slot',
  'order_id': 'o1',
  'car_no': 'RDS-6583',
  'stage': 'return',
  'slot': slot,
  'assessable': assessable,
  'assessable_reason': reason,
  'retake_required': retake,
  'retake_hint': hint,
  'coverage_adequate': true,
  'cleanliness': cleanliness,
  'items': items,
  'observed_damages': const <Object?>[],
  'max_severity': 'none',
  'error': error,
};

void main() {
  late Directory tmp;
  late File frame;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('l0_shot');
    frame = File('${tmp.path}/shot.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF]);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  CapturedShot shot({bool manual = false}) => CapturedShot(
    file: frame,
    report: {'passed': !manual, 'capture_mode': manual ? 'manual' : 'auto'},
    manual: manual,
  );

  /// A session wired to a canned L1, with the requests it made recorded.
  (ReturnSession, List<String>) sessionReturning(
    Map<String, Object?> Function(String slot) respond,
  ) {
    final seen = <String>[];
    final client = MockClient((request) async {
      final body = utf8.decode(request.bodyBytes, allowMalformed: true);
      // http writes non-ASCII multipart fields with their own content-type
      // header, so read each part as "everything up to the next boundary"
      // rather than assuming the value sits right after the disposition line.
      String field(String name) =>
          body.split('name="$name"').last.split('\r\n--').first;
      final slot = CaptureSpot.values
          .map((s) => s.label)
          .firstWhere(field('slot').contains, orElse: () => '');
      seen.add('$slot retake=${field('retake').contains('true')}');
      return http.Response(
        jsonEncode(respond(slot)),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final session = ReturnSession(
      orderId: 'o1',
      carNo: 'RDS-6583',
      api: InspectionApi(baseUrl: 'http://test', client: client),
    )..live = true;
    return (session, seen);
  }

  test('a readable photo settles as passed', () async {
    final (session, _) = sessionReturning((slot) => l1Json(slot: slot));
    await session.submit(CaptureSpot.frontLeft, shot());

    final status = session.statusOf(CaptureSpot.frontLeft);
    expect(status.phase, SlotPhase.passed);
    expect(status.file, frame);
    expect(session.anyScreening, isFalse);
  });

  test("an unreadable photo asks for a retake in L1's own words", () async {
    final (session, _) = sessionReturning(
      (slot) => l1Json(
        slot: slot,
        assessable: false,
        reason: '車身左側整片反光，漆面狀況無法判讀',
        retake: true,
        hint: '請換一個角度避開光源',
      ),
    );
    await session.submit(CaptureSpot.rearRight, shot());

    expect(session.statusOf(CaptureSpot.rearRight).phase, SlotPhase.retake);
    expect(session.retakeSpots, [CaptureSpot.rearRight]);

    final issue = session.analysis.issue!;
    expect(issue.emphasis, '右後');
    expect(issue.body, contains('整片反光'));
    expect(issue.body, contains('避開光源'));
    expect(issue.retakeSpot, CaptureSpot.rearRight);
    expect(session.analysis.photo.ok, isFalse);
  });

  test('a dirty cabin outranks a photo that needs retaking', () async {
    // L3 rule 1 before rule 6, and the driver-facing flow has to agree: dirt is
    // the only thing anyone is asked to fix on the spot.
    final (session, _) = sessionReturning(
      (slot) => slot == '後座'
          ? l1Json(slot: slot, cleanliness: '髒汙', items: ['飲料杯', '紙袋'])
          : l1Json(
              slot: slot,
              assessable: false,
              reason: '反光',
              retake: true,
            ),
    );
    await session.submit(CaptureSpot.frontLeft, shot());
    await session.submit(CaptureSpot.interiorRear, shot());

    final analysis = session.analysis;
    expect(analysis.cabin.ok, isFalse);
    expect(analysis.cabin.resultLabel, contains('飲料杯'));
    expect(analysis.issue!.retakeSpot, CaptureSpot.interiorRear);
    expect(analysis.issue!.title, '車內偵測到垃圾');
  });

  test('a clean cabin and readable photos produce no issue', () async {
    final (session, _) = sessionReturning(
      (slot) => slot == '後座'
          ? l1Json(slot: slot, cleanliness: '乾淨')
          : l1Json(slot: slot),
    );
    for (final spot in CaptureSpot.values) {
      await session.submit(spot, shot());
    }
    final analysis = session.analysis;
    expect(analysis.allClear, isTrue);
    expect(analysis.photo.resultLabel, '7 張照片皆可判讀');
    expect(analysis.continueLabel, '繼續還車');
  });

  test('L1 reporting its own failure releases the driver, not the car', () async {
    final (session, _) = sessionReturning(
      (slot) => l1Json(slot: slot, error: 'gemini timeout'),
    );
    await session.submit(CaptureSpot.frontLeft, shot());

    final status = session.statusOf(CaptureSpot.frontLeft);
    expect(status.phase, SlotPhase.failed);
    expect(status.message, contains('稍後通知'));
    // Nothing is asked of the driver: L3 handles the car via system_error.
    expect(session.analysis.issue, isNull);
  });

  test('an unreachable service is a failure, not a retake loop', () async {
    final session = ReturnSession(
      orderId: 'o1',
      carNo: 'RDS-6583',
      api: InspectionApi(
        baseUrl: 'http://test',
        client: MockClient((_) async => http.Response('nope', 500)),
      ),
    )..live = true;

    await session.submit(CaptureSpot.frontLeft, shot());
    expect(session.statusOf(CaptureSpot.frontLeft).phase, SlotPhase.failed);
    expect(session.retakeSpots, isEmpty);
  });

  test('the second shot of a slot is flagged as a retake', () async {
    // The retake budget lives on the server; it can only count if the client
    // says which submissions are repeats. Clearing the tile for the driver must
    // not reset that count.
    final (session, seen) = sessionReturning((slot) => l1Json(slot: slot));

    await session.submit(CaptureSpot.frontLeft, shot());
    session.clear(CaptureSpot.frontLeft);
    await session.submit(CaptureSpot.frontLeft, shot());

    expect(seen, ['左前 retake=false', '左前 retake=true']);
  });

  test('nothing submitted means nothing is claimed', () async {
    final (session, _) = sessionReturning((slot) => l1Json(slot: slot));
    expect(session.reportedSpots, isEmpty);
    expect(session.anyScreening, isFalse);
    expect(session.analysis.allClear, isTrue);
  });
}

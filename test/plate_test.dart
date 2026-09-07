import 'package:flutter_test/flutter_test.dart';
import 'package:irent_pulse/l0/plate.dart';

/// The 車牌比對 rules.
///
/// These are worth testing precisely because the camera path around them cannot
/// be: the OCR is a method channel into ML Kit, so on this machine there is no
/// way to prove the check behaves. What *can* be proved is the part that
/// decides whether a driver gets told to go away — and that is all in here.
void main() {
  group('normalisePlate', () {
    test('strips separators and case', () {
      expect(normalisePlate('rds-6583'), normalisePlate('RDS 6583'));
      expect(normalisePlate('RDS・6583'), normalisePlate('RDS-6583'));
    });

    test('folds the glyphs OCR confuses', () {
      // O/0, I/1, S/5, B/8 — the pairs a plate typeface loses at distance.
      expect(normalisePlate('AOI-1B5'), normalisePlate('A01-185'));
    });
  });

  group('extractPlates', () {
    test('finds a plate among the rest of a car\'s text', () {
      final found = extractPlates('TOYOTA\nCOROLLA CROSS\nRDS-6583\nHYBRID');
      expect(found, contains(normalisePlate('RDS-6583')));
    });

    test('rejects pure-alphabetic badges', () {
      // The regression this pins down: `COROLLA` folds to `C0R011A`, so a
      // digit test applied *after* normalisation passes it. The filter has to
      // run on the raw characters.
      expect(extractPlates('COROLLA'), isEmpty);
      expect(extractPlates('HYBRID'), isEmpty);
    });

    test('rejects tokens too short or too long to be a plate', () {
      expect(extractPlates('AB-1'), isEmpty);
      expect(extractPlates('1234-56789'), isEmpty);
    });
  });

  group('matchPlates', () {
    test('matches the rented car exactly', () {
      expect(
        matchPlates(extractPlates('RDS-6583'), 'RDS-6583'),
        PlateMatch.match,
      );
    });

    test('forgives one misread character', () {
      // The direction that has to be forgiving: a plate read at distance in the
      // rain loses a character, and refusing that reading strands a driver in
      // front of their own car.
      expect(
        matchPlates(extractPlates('RDS-6589'), 'RDS-6583'),
        PlateMatch.match,
      );
    });

    test('a genuinely different car is a mismatch', () {
      expect(
        matchPlates(extractPlates('ABC-1234'), 'RDS-6583'),
        PlateMatch.mismatch,
      );
    });

    test('the right plate anywhere in frame wins', () {
      // Both cars in shot at a corner slot. Seeing ours is proof; seeing the
      // neighbour's is not evidence against.
      expect(
        matchPlates(extractPlates('ABC-1234 RDS-6583'), 'RDS-6583'),
        PlateMatch.match,
      );
    });

    test('nothing readable says nothing', () {
      expect(matchPlates(const [], 'RDS-6583'), PlateMatch.unknown);
      expect(matchPlates(extractPlates('COROLLA'), 'RDS-6583'), PlateMatch.unknown);
    });
  });

  group('PlateWatcher', () {
    test('starts silent', () {
      expect(PlateWatcher(expected: 'RDS-6583').state, PlateMatch.unknown);
    });

    test('a single stray reading does not turn the frame red', () {
      final watcher = PlateWatcher(expected: 'RDS-6583');
      watcher.observe('ABC-1234');
      expect(watcher.state, PlateMatch.unknown);
      watcher.observe('ABC-1234');
      expect(watcher.state, PlateMatch.unknown);
    });

    test('a plate read consistently as another car does', () {
      final watcher = PlateWatcher(expected: 'RDS-6583');
      for (var i = 0; i < PlateWatcher.mismatchStreak; i++) {
        watcher.observe('ABC-1234');
      }
      expect(watcher.state, PlateMatch.mismatch);
    });

    test('a text-rich scene does not turn the frame red', () {
      // Straight off the bench: the camera caught a screen full of prose and
      // every reading produced a different handful of plate-shaped junk. None
      // of it repeats, so none of it is evidence.
      final watcher = PlateWatcher(expected: 'REN-0000');
      watcher.observe('5105PN6 493RNET 21MA6E');
      watcher.observe('C1AUDE50 5125PN6 R1NF4');
      watcher.observe('CARN01E 5145PN6 DN6R07');
      watcher.observe('3RENT10 5105PN61 515PN6');
      expect(watcher.state, PlateMatch.unknown);
    });

    test('the same wrong plate three times still turns it red', () {
      // The distinction that matters: junk changes every frame, a car does not.
      final watcher = PlateWatcher(expected: 'REN-0000');
      watcher.observe('ABC-1234 5105PN6');
      watcher.observe('ABC-1234 R1NF4');
      watcher.observe('ABC-1234 DN6R07');
      expect(watcher.state, PlateMatch.mismatch);
    });

    test('a match is believed at once', () {
      final watcher = PlateWatcher(expected: 'RDS-6583');
      watcher.observe('RDS-6583');
      expect(watcher.state, PlateMatch.match);
    });

    test('a confirmed match is not overturned by the car parked next to it', () {
      final watcher = PlateWatcher(expected: 'RDS-6583');
      watcher.observe('RDS-6583');
      for (var i = 0; i < PlateWatcher.mismatchStreak * 2; i++) {
        watcher.observe('ABC-1234');
      }
      expect(watcher.state, PlateMatch.match);
    });

    test('unreadable frames are not evidence', () {
      final watcher = PlateWatcher(expected: 'RDS-6583');
      for (var i = 0; i < PlateWatcher.mismatchStreak * 2; i++) {
        watcher.observe(null);
        watcher.observe('');
        watcher.observe('COROLLA CROSS');
      }
      expect(watcher.state, PlateMatch.unknown);
    });

    test('restart clears a pending mismatch but keeps a confirmed match', () {
      final wrong = PlateWatcher(expected: 'RDS-6583');
      for (var i = 0; i < PlateWatcher.mismatchStreak; i++) {
        wrong.observe('ABC-1234');
      }
      wrong.restart();
      expect(wrong.state, PlateMatch.unknown);

      final right = PlateWatcher(expected: 'RDS-6583');
      right.observe('RDS-6583');
      right.restart();
      // The match is about the car, not about the shot — the driver walks to
      // the next corner where there is no plate to see.
      expect(right.state, PlateMatch.match);
    });

    test('no expected plate means the check never fires', () {
      final watcher = PlateWatcher(expected: '');
      for (var i = 0; i < PlateWatcher.mismatchStreak * 2; i++) {
        watcher.observe('ABC-1234');
      }
      expect(watcher.state, PlateMatch.unknown);
    });
  });
}

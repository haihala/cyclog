import 'package:flutter_test/flutter_test.dart';
import 'package:cyclog/calendar.dart';
import 'package:cyclog/models.dart';

Occurrence occ(String start, [String? end]) => Occurrence(
      trackerId: 1,
      start: Day.parse(start),
      end: end == null ? null : Day.parse(end),
    );

void main() {
  group('coveredEnd', () {
    test('an open-ended entry covers only its start day', () {
      final o = occ('2025-03-05');
      expect(coveredEnd(o), Day.parse('2025-03-05'));
    });

    test('a closed entry covers through its end day', () {
      expect(coveredEnd(occ('2025-03-05', '2025-03-09')),
          Day.parse('2025-03-09'));
    });
  });

  group('startOfWeek', () {
    test('a Monday is its own week start', () {
      // 2025-03-03 is a Monday.
      expect(startOfWeek(Day.parse('2025-03-03')), Day.parse('2025-03-03'));
    });

    test('a Sunday belongs to the week that began six days earlier', () {
      // 2025-03-09 is a Sunday.
      expect(startOfWeek(Day.parse('2025-03-09')), Day.parse('2025-03-03'));
    });

    test('works across a month boundary', () {
      // 2025-04-02 is a Wednesday; its Monday is in March.
      expect(startOfWeek(Day.parse('2025-04-02')), Day.parse('2025-03-31'));
    });

    test('works across a year boundary', () {
      // 2025-01-01 is a Wednesday; its Monday is 2024-12-30.
      expect(startOfWeek(Day.parse('2025-01-01')), Day.parse('2024-12-30'));
    });
  });

  group('month grid', () {
    test('starts on the Monday on or before the first of the month', () {
      // 1 Mar 2025 is a Saturday, so the grid starts Mon 24 Feb.
      expect(monthGridStart(2025, 3), Day.parse('2025-02-24'));
    });

    test('a month beginning on a Monday starts on the first', () {
      // 1 Sep 2025 is a Monday.
      expect(monthGridStart(2025, 9), Day.parse('2025-09-01'));
    });

    test('always yields six consecutive week starts', () {
      final weeks = monthGridWeeks(2025, 3);
      expect(weeks.length, 6);
      for (var i = 1; i < weeks.length; i++) {
        expect(weeks[i - 1].daysTo(weeks[i]), 7);
      }
    });

    test('the grid always spans the whole month', () {
      // February 2026 is short; the grid must still cover it entirely.
      final weeks = monthGridWeeks(2026, 2);
      final gridEnd = weeks.last.addDays(6);
      expect(weeks.first <= Day.parse('2026-02-01'), isTrue);
      expect(gridEnd >= Day.parse('2026-02-28'), isTrue);
    });
  });

  group('month arithmetic', () {
    test('counts months across years', () {
      expect(monthsBetween(Day.parse('2024-11-01'), Day.parse('2025-02-01')),
          3);
      expect(monthsBetween(Day.parse('2025-02-01'), Day.parse('2024-11-01')),
          -3);
      expect(monthsBetween(Day.parse('2025-05-20'), Day.parse('2025-05-01')),
          0);
    });

    test('adding months rolls over the year', () {
      expect(addMonths(2025, 11, 3), (year: 2026, month: 2));
      expect(addMonths(2025, 1, -1), (year: 2024, month: 12));
      expect(addMonths(2025, 6, 0), (year: 2025, month: 6));
      expect(addMonths(2025, 12, 1), (year: 2026, month: 1));
    });

    test('addMonths is the inverse of monthsBetween', () {
      final r = addMonths(2025, 3, 14);
      expect(
        monthsBetween(Day.parse('2025-03-01'), Day(r.year, r.month, 1)),
        14,
      );
    });
  });

  group('segmentsForWeek', () {
    // Week of Mon 3 Mar 2025 through Sun 9 Mar 2025.
    final week = Day.parse('2025-03-03');

    test('ignores entries that do not touch the week', () {
      final segs = segmentsForWeek(
        [occ('2025-02-01', '2025-02-10'), occ('2025-04-01')],
        week,
      );
      expect(segs, isEmpty);
    });

    test('a single day maps to one column', () {
      final segs = segmentsForWeek([occ('2025-03-05')], week);
      expect(segs.length, 1);
      expect(segs.single.startCol, 2);
      expect(segs.single.endCol, 2);
      expect(segs.single.columnSpan, 1);
      expect(segs.single.continuesBefore, isFalse);
      expect(segs.single.continuesAfter, isFalse);
    });

    test('an entry inside the week spans its own columns', () {
      final segs = segmentsForWeek([occ('2025-03-04', '2025-03-06')], week);
      expect(segs.single.startCol, 1);
      expect(segs.single.endCol, 3);
      expect(segs.single.columnSpan, 3);
    });

    test('an entry starting earlier is clipped and flagged', () {
      final segs = segmentsForWeek([occ('2025-02-27', '2025-03-05')], week);
      expect(segs.single.startCol, 0);
      expect(segs.single.endCol, 2);
      expect(segs.single.continuesBefore, isTrue);
      expect(segs.single.continuesAfter, isFalse);
    });

    test('an entry running later is clipped and flagged', () {
      final segs = segmentsForWeek([occ('2025-03-06', '2025-03-20')], week);
      expect(segs.single.startCol, 3);
      expect(segs.single.endCol, 6);
      expect(segs.single.continuesAfter, isTrue);
      expect(segs.single.continuesBefore, isFalse);
    });

    test('an entry covering the whole week fills every column', () {
      final segs = segmentsForWeek([occ('2025-01-01', '2025-12-31')], week);
      expect(segs.single.startCol, 0);
      expect(segs.single.endCol, 6);
      expect(segs.single.continuesBefore, isTrue);
      expect(segs.single.continuesAfter, isTrue);
    });

    test('an entry ending exactly on Sunday is not flagged as continuing', () {
      final segs = segmentsForWeek([occ('2025-03-08', '2025-03-09')], week);
      expect(segs.single.endCol, 6);
      expect(segs.single.continuesAfter, isFalse);
    });

    test('an entry starting exactly on Monday is not flagged as continuing',
        () {
      final segs = segmentsForWeek([occ('2025-03-03', '2025-03-04')], week);
      expect(segs.single.startCol, 0);
      expect(segs.single.continuesBefore, isFalse);
    });

    test('an open-ended entry occupies only its start column', () {
      final segs = segmentsForWeek([occ('2025-03-07')], week);
      expect(segs.single.startCol, 4);
      expect(segs.single.endCol, 4);
      expect(segs.single.continuesAfter, isFalse);
    });

    test('results are ordered by start column', () {
      final segs = segmentsForWeek(
        [occ('2025-03-08'), occ('2025-03-04'), occ('2025-03-06')],
        week,
      );
      expect(segs.map((s) => s.startCol).toList(), [1, 3, 5]);
    });

    test('overlapping entries are all kept, never merged or dropped', () {
      final segs = segmentsForWeek(
        [occ('2025-03-03', '2025-03-06'), occ('2025-03-05', '2025-03-09')],
        week,
      );
      expect(segs.length, 2);
    });

    test('duplicate entries on the same day both appear', () {
      final segs = segmentsForWeek([occ('2025-03-05'), occ('2025-03-05')],
          week);
      expect(segs.length, 2);
    });
  });

  group('entriesOnDay', () {
    test('includes an entry whose range covers the day', () {
      final list = [occ('2025-03-01', '2025-03-10')];
      expect(entriesOnDay(list, Day.parse('2025-03-05')).length, 1);
    });

    test('includes the boundary days', () {
      final list = [occ('2025-03-01', '2025-03-10')];
      expect(entriesOnDay(list, Day.parse('2025-03-01')).length, 1);
      expect(entriesOnDay(list, Day.parse('2025-03-10')).length, 1);
    });

    test('excludes days outside the range', () {
      final list = [occ('2025-03-01', '2025-03-10')];
      expect(entriesOnDay(list, Day.parse('2025-02-28')), isEmpty);
      expect(entriesOnDay(list, Day.parse('2025-03-11')), isEmpty);
    });

    test('an open-ended entry matches only its start day', () {
      final list = [occ('2025-03-05')];
      expect(entriesOnDay(list, Day.parse('2025-03-05')).length, 1);
      expect(entriesOnDay(list, Day.parse('2025-03-06')), isEmpty);
    });
  });

  group('isInMonth', () {
    test('distinguishes borrowed neighbouring days', () {
      expect(isInMonth(Day.parse('2025-03-01'), 2025, 3), isTrue);
      expect(isInMonth(Day.parse('2025-02-28'), 2025, 3), isFalse);
      expect(isInMonth(Day.parse('2024-03-15'), 2025, 3), isFalse);
    });
  });
}

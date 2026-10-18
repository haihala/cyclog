import 'package:flutter_test/flutter_test.dart';
import 'package:cyclog/models.dart';
import 'package:cyclog/stats.dart';

Occurrence occ(String start, [String? end]) => Occurrence(
      trackerId: 1,
      start: Day.parse(start),
      end: end == null ? null : Day.parse(end),
    );

void main() {
  group('Day', () {
    test('round-trips through ISO', () {
      final d = Day.parse('2025-03-07');
      expect(d.toIso(), '2025-03-07');
      expect(d.year, 2025);
      expect(d.month, 3);
      expect(d.day, 7);
    });

    test('counts days across a month boundary', () {
      expect(Day.parse('2025-01-28').daysTo(Day.parse('2025-02-03')), 6);
    });

    test('counts days across a leap day', () {
      expect(Day.parse('2024-02-28').daysTo(Day.parse('2024-03-01')), 2);
      expect(Day.parse('2023-02-28').daysTo(Day.parse('2023-03-01')), 1);
    });

    test('counts days across a DST transition', () {
      // Spring forward in most of Europe/North America falls in Mar.
      expect(Day.parse('2025-03-29').daysTo(Day.parse('2025-03-31')), 2);
      // Autumn back.
      expect(Day.parse('2025-10-25').daysTo(Day.parse('2025-10-27')), 2);
    });

    test('negative when target is earlier', () {
      expect(Day.parse('2025-05-10').daysTo(Day.parse('2025-05-01')), -9);
    });

    test('addDays is the inverse of daysTo', () {
      final a = Day.parse('2025-10-25');
      expect(a.addDays(37).let((b) => a.daysTo(b)), 37);
      expect(a.addDays(-37).let((b) => a.daysTo(b)), -37);
    });

    test('orders correctly', () {
      expect(Day.parse('2025-01-02') < Day.parse('2025-02-01'), isTrue);
      expect(Day.parse('2024-12-31') < Day.parse('2025-01-01'), isTrue);
      expect(Day.parse('2025-01-01') == Day(2025, 1, 1), isTrue);
    });
  });

  group('Occurrence', () {
    test('length is inclusive of both ends', () {
      expect(occ('2025-03-01', '2025-03-05').lengthDays, 5);
      expect(occ('2025-03-01', '2025-03-01').lengthDays, 1);
    });

    test('length is null without an end, never zero or guessed', () {
      expect(occ('2025-03-01').lengthDays, isNull);
    });
  });

  group('SampleStats', () {
    test('mean, median and spread of a known sample', () {
      const s = SampleStats([2, 4, 4, 4, 5, 5, 7, 9]);
      expect(s.mean, 5.0);
      expect(s.median, 4.5);
      expect(s.stdDev, closeTo(2.138, 0.001));
      expect(s.min, 2);
      expect(s.max, 9);
    });

    test('median of an odd-sized sample', () {
      expect(const SampleStats([5, 1, 3]).median, 3.0);
    });

    test('spread is unknown, not zero, for a single observation', () {
      expect(const SampleStats([30]).stdDev.isNaN, isTrue);
      expect(const SampleStats([30]).predictionMargin(ConfidenceLevel.eighty),
          isNull);
    });

    test('prediction margin widens with confidence level', () {
      const s = SampleStats([28, 30, 26, 34, 29]);
      final fifty = s.predictionMargin(ConfidenceLevel.fifty)!;
      final eighty = s.predictionMargin(ConfidenceLevel.eighty)!;
      final ninetyFive = s.predictionMargin(ConfidenceLevel.ninetyFive)!;
      expect(fifty, lessThan(eighty));
      expect(eighty, lessThan(ninetyFive));
    });

    test('prediction margin matches the t formula', () {
      const s = SampleStats([28, 30, 26, 34, 29]);
      // mean = 29.4, s.d. = 2.96648, n = 5, t(4, 95%) = 2.776
      // margin = 2.776 * 2.96648 * sqrt(1 + 1/5) = 9.0209
      expect(s.mean, closeTo(29.4, 0.0001));
      expect(s.stdDev, closeTo(2.96648, 0.0001));
      expect(
        s.predictionMargin(ConfidenceLevel.ninetyFive),
        closeTo(9.0209, 0.001),
      );
    });

    test('an irregular sample yields a wider margin than a regular one', () {
      const regular = SampleStats([28, 28, 29, 28, 29]);
      const irregular = SampleStats([24, 38, 26, 45, 31]);
      expect(
        irregular.predictionMargin(ConfidenceLevel.eighty)!,
        greaterThan(regular.predictionMargin(ConfidenceLevel.eighty)! * 3),
      );
    });
  });

  group('computeStats', () {
    test('no entries produces no estimate and no invented figures', () {
      final s = computeStats([]);
      expect(s.occurrenceCount, 0);
      expect(s.nextStart, isNull);
      expect(s.lastStart, isNull);
      expect(s.gaps.n, 0);
      expect(s.meanLength, isNull);
    });

    test('a single entry produces no estimate', () {
      final s = computeStats([occ('2025-01-01')]);
      expect(s.occurrenceCount, 1);
      expect(s.nextStart, isNull);
      expect(s.lastStart, Day.parse('2025-01-01'));
    });

    test('two entries give a point estimate but no range', () {
      final s = computeStats([occ('2025-01-01'), occ('2025-01-29')]);
      expect(s.gaps.values, [28]);
      final est = s.nextStart!;
      expect(est.point, Day.parse('2025-02-26'));
      expect(est.hasRange, isFalse);
      expect(est.basedOnGaps, 1);
    });

    test('gaps are measured start-to-start', () {
      final s = computeStats([
        occ('2025-01-01', '2025-01-06'),
        occ('2025-02-02', '2025-02-05'),
        occ('2025-03-01', '2025-03-07'),
      ]);
      expect(s.gaps.values, [32, 27]);
    });

    test('entries given out of order are sorted, not rejected', () {
      final s = computeStats([
        occ('2025-03-01'),
        occ('2025-01-01'),
        occ('2025-02-02'),
      ]);
      expect(s.gaps.values, [32, 27]);
      expect(s.firstStart, Day.parse('2025-01-01'));
      expect(s.lastStart, Day.parse('2025-03-01'));
    });

    test('an irregular cycle produces a wide but honest range', () {
      final s = computeStats(
        [
          occ('2025-01-01'),
          occ('2025-01-25'), // 24
          occ('2025-03-04'), // 38
          occ('2025-03-30'), // 26
          occ('2025-05-14'), // 45
        ],
        level: ConfidenceLevel.eighty,
      );
      expect(s.gaps.values, [24, 38, 26, 45]);
      final est = s.nextStart!;
      expect(est.hasRange, isTrue);
      // The range must be wide enough to reflect real variability.
      expect(est.rangeDays!, greaterThan(20));
      // And it must bracket the point estimate.
      expect(est.earliest! < est.point, isTrue);
      expect(est.latest! > est.point, isTrue);
    });

    test('range bounds are widened outward, never narrowed by rounding', () {
      final s = computeStats([
        occ('2025-01-01'),
        occ('2025-01-29'),
        occ('2025-02-28'),
        occ('2025-03-25'),
      ]);
      final est = s.nextStart!;
      final margin = s.gaps.predictionMargin(est.level)!;
      final mean = s.gaps.mean;
      final last = s.lastStart!;
      expect(last.daysTo(est.earliest!), (mean - margin).floor());
      expect(last.daysTo(est.latest!), (mean + margin).ceil());
    });

    test('a very long gap is kept, never discarded as an outlier', () {
      final s = computeStats([
        occ('2025-01-01'),
        occ('2025-01-29'), // 28
        occ('2025-07-01'), // 153
      ]);
      expect(s.gaps.values, [28, 153]);
      expect(s.gaps.max, 153);
      // The estimate reflects the long gap rather than ignoring it.
      expect(s.gaps.mean, closeTo(90.5, 0.01));
    });

    test('repeated entries on the same day are kept as a zero gap', () {
      final s = computeStats([occ('2025-01-01'), occ('2025-01-01')]);
      expect(s.occurrenceCount, 2);
      expect(s.gaps.values, [0]);
    });

    test('window keeps only the most recent gaps', () {
      final all = [
        occ('2025-01-01'),
        occ('2025-01-29'), // 28
        occ('2025-03-04'), // 34
        occ('2025-03-30'), // 26
        occ('2025-05-14'), // 45
      ];
      expect(computeStats(all).gaps.values, [28, 34, 26, 45]);
      expect(computeStats(all, windowSize: 2).gaps.values, [26, 45]);
      // A window larger than the data uses everything, without padding.
      expect(computeStats(all, windowSize: 99).gaps.values.length, 4);
    });

    test('open-ended entries are counted, not treated as errors', () {
      final s = computeStats([
        occ('2025-01-01', '2025-01-05'),
        occ('2025-02-01'),
        occ('2025-03-01', '2025-03-04'),
      ]);
      expect(s.openEndedCount, 1);
      expect(s.lengths.values, [5, 4]);
      expect(s.meanLength, 4.5);
      // The open entry still contributes its start to the gaps.
      expect(s.gaps.values, [31, 28]);
    });

    test('lengths are empty rather than guessed when no ends exist', () {
      final s = computeStats([occ('2025-01-01'), occ('2025-02-01')]);
      expect(s.lengths.isEmpty, isTrue);
      expect(s.meanLength, isNull);
      expect(s.openEndedCount, 2);
    });

    test('variability is reported as a ratio of the mean', () {
      final steady = computeStats([
        occ('2025-01-01'),
        occ('2025-01-29'),
        occ('2025-02-26'),
      ]);
      final erratic = computeStats([
        occ('2025-01-01'),
        occ('2025-01-15'),
        occ('2025-04-01'),
      ]);
      expect(steady.gapVariability!, lessThan(erratic.gapVariability!));
    });
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// Descriptive statistics and forward estimates.
///
/// Everything in here is derived *only* from what the user actually recorded.
/// There is no imputation, no outlier rejection, no "you probably forgot to
/// log this" inference. If the data is irregular, the resulting interval is
/// wide, and that wide interval is the honest answer.
library;

import 'dart:math' as math;

import 'models.dart';

/// Confidence level for prediction intervals.
enum ConfidenceLevel {
  fifty(0.50, '50%'),
  eighty(0.80, '80%'),
  ninetyFive(0.95, '95%');

  const ConfidenceLevel(this.value, this.label);

  final double value;
  final String label;

  static ConfidenceLevel fromValue(double v) {
    return ConfidenceLevel.values.firstWhere(
      (e) => (e.value - v).abs() < 0.001,
      orElse: () => ConfidenceLevel.eighty,
    );
  }
}

/// Summary of a list of numbers. All fields are plain descriptions of the
/// sample; none of them are adjusted or cleaned.
class SampleStats {
  /// The observations, in the order they occurred.
  final List<int> values;

  const SampleStats(this.values);

  int get n => values.length;
  bool get isEmpty => values.isEmpty;

  double get mean {
    if (values.isEmpty) return double.nan;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// Sample standard deviation (n-1). NaN when fewer than 2 observations,
  /// because with one observation the spread is genuinely unknown.
  double get stdDev {
    if (values.length < 2) return double.nan;
    final m = mean;
    final sumSq = values.fold<double>(0, (acc, v) => acc + math.pow(v - m, 2));
    return math.sqrt(sumSq / (values.length - 1));
  }

  double get median {
    if (values.isEmpty) return double.nan;
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid].toDouble();
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  int? get min => values.isEmpty ? null : values.reduce(math.min);
  int? get max => values.isEmpty ? null : values.reduce(math.max);

  /// Half-width of the prediction interval for the *next single* observation.
  ///
  /// Uses the Student-t prediction interval: t * s * sqrt(1 + 1/n). This is
  /// deliberately the prediction interval for one new observation, not the
  /// confidence interval of the mean — the user wants to know when the next
  /// event lands, not where the long-run average sits.
  ///
  /// Returns null when there are fewer than 2 observations.
  double? predictionMargin(ConfidenceLevel level) {
    if (values.length < 2) return null;
    final s = stdDev;
    if (s.isNaN) return null;
    final t = _tQuantile(values.length - 1, level);
    return t * s * math.sqrt(1 + 1 / values.length);
  }
}

/// Two-sided Student-t critical value. Table for df 1..30, normal
/// approximation beyond that (the error there is well under a tenth of a day).
double _tQuantile(int df, ConfidenceLevel level) {
  const table = <ConfidenceLevel, List<double>>{
    ConfidenceLevel.fifty: [
      1.000, 0.816, 0.765, 0.741, 0.727, 0.718, 0.711, 0.706, 0.703, 0.700, //
      0.697, 0.695, 0.694, 0.692, 0.691, 0.690, 0.689, 0.688, 0.688, 0.687, //
      0.686, 0.686, 0.685, 0.685, 0.684, 0.684, 0.684, 0.683, 0.683, 0.683,
    ],
    ConfidenceLevel.eighty: [
      3.078, 1.886, 1.638, 1.533, 1.476, 1.440, 1.415, 1.397, 1.383, 1.372, //
      1.363, 1.356, 1.350, 1.345, 1.341, 1.337, 1.333, 1.330, 1.328, 1.325, //
      1.323, 1.321, 1.319, 1.318, 1.316, 1.315, 1.314, 1.313, 1.311, 1.310,
    ],
    ConfidenceLevel.ninetyFive: [
      12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306, 2.262, 2.228, //
      2.201, 2.179, 2.160, 2.145, 2.131, 2.120, 2.110, 2.101, 2.093, 2.086, //
      2.080, 2.074, 2.069, 2.064, 2.060, 2.056, 2.052, 2.048, 2.045, 2.042,
    ],
  };
  const normal = <ConfidenceLevel, double>{
    ConfidenceLevel.fifty: 0.6745,
    ConfidenceLevel.eighty: 1.2816,
    ConfidenceLevel.ninetyFive: 1.9600,
  };

  if (df < 1) return normal[level]!;
  final row = table[level]!;
  if (df <= row.length) return row[df - 1];
  return normal[level]!;
}

/// A forward estimate for the next occurrence.
class Estimate {
  /// Most likely next start, from the mean gap between recorded starts.
  final Day point;

  /// Interval bounds. Null when there are too few gaps to estimate spread.
  final Day? earliest;
  final Day? latest;

  /// Number of gaps the estimate is based on.
  final int basedOnGaps;

  final ConfidenceLevel level;

  const Estimate({
    required this.point,
    required this.earliest,
    required this.latest,
    required this.basedOnGaps,
    required this.level,
  });

  bool get hasRange => earliest != null && latest != null;

  /// Width of the interval in days, or null if there is no interval.
  int? get rangeDays =>
      hasRange ? earliest!.daysTo(latest!) : null;
}

/// All derived figures for one tracker.
class TrackerStats {
  /// Gaps in days between consecutive recorded starts.
  final SampleStats gaps;

  /// Inclusive lengths of occurrences that have a recorded end.
  final SampleStats lengths;

  /// How many occurrences have no recorded end. Reported as a neutral fact,
  /// never as a problem to fix.
  final int openEndedCount;

  final int occurrenceCount;

  final Day? lastStart;
  final Day? firstStart;

  final Estimate? nextStart;

  /// Typical length rounded for display, null when nothing has an end.
  final double? meanLength;

  const TrackerStats({
    required this.gaps,
    required this.lengths,
    required this.openEndedCount,
    required this.occurrenceCount,
    required this.lastStart,
    required this.firstStart,
    required this.nextStart,
    required this.meanLength,
  });

  /// Coefficient of variation of the gaps, as a plain measure of how
  /// irregular the recorded data is. Null when it can't be computed.
  double? get gapVariability {
    if (gaps.n < 2) return null;
    final m = gaps.mean;
    if (m <= 0) return null;
    final s = gaps.stdDev;
    if (s.isNaN) return null;
    return s / m;
  }
}

/// Computes statistics for a tracker's occurrences.
///
/// [windowSize] optionally restricts the calculation to the most recent N
/// gaps. This is a user choice about which data to weigh, not an automatic
/// judgement about which data is valid.
///
/// The window deliberately applies to gaps only. Length figures always use
/// every entry that has a recorded end, matching the "Gaps used" wording in
/// settings.
TrackerStats computeStats(
  List<Occurrence> occurrences, {
  ConfidenceLevel level = ConfidenceLevel.eighty,
  int? windowSize,
}) {
  final sorted = [...occurrences]..sort((a, b) => a.start.compareTo(b.start));

  final gapValues = <int>[];
  for (var i = 1; i < sorted.length; i++) {
    gapValues.add(sorted[i - 1].start.daysTo(sorted[i].start));
  }

  var windowed = gapValues;
  if (windowSize != null && windowSize > 0 && gapValues.length > windowSize) {
    windowed = gapValues.sublist(gapValues.length - windowSize);
  }

  final lengthValues = <int>[];
  var openEnded = 0;
  for (final o in sorted) {
    final len = o.lengthDays;
    if (len == null) {
      openEnded++;
    } else {
      lengthValues.add(len);
    }
  }

  final gaps = SampleStats(windowed);
  final lengths = SampleStats(lengthValues);

  final lastStart = sorted.isEmpty ? null : sorted.last.start;
  final firstStart = sorted.isEmpty ? null : sorted.first.start;

  Estimate? estimate;
  if (lastStart != null && gaps.n >= 1) {
    final meanGap = gaps.mean;
    final point = lastStart.addDays(meanGap.round());
    final margin = gaps.predictionMargin(level);

    Day? earliest;
    Day? latest;
    if (margin != null) {
      // Floor/ceil rather than round, so the stated range is never narrower
      // than the arithmetic supports.
      earliest = lastStart.addDays((meanGap - margin).floor());
      latest = lastStart.addDays((meanGap + margin).ceil());
    }

    estimate = Estimate(
      point: point,
      earliest: earliest,
      latest: latest,
      basedOnGaps: gaps.n,
      level: level,
    );
  }

  return TrackerStats(
    gaps: gaps,
    lengths: lengths,
    openEndedCount: openEnded,
    occurrenceCount: sorted.length,
    lastStart: lastStart,
    firstStart: firstStart,
    nextStart: estimate,
    meanLength: lengths.isEmpty ? null : lengths.mean,
  );
}

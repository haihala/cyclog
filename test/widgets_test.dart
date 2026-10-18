import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cyclog/models.dart';
import 'package:cyclog/stats.dart';
import 'package:cyclog/widgets/stat_views.dart';

const _tracker = Tracker(
  id: 1,
  name: 'Thing',
  hasDuration: true,
  color: 0xFF1E88E5,
);

Occurrence occ(String start, [String? end]) => Occurrence(
      trackerId: 1,
      start: Day.parse(start),
      end: end == null ? null : Day.parse(end),
    );

Future<void> pumpWidget(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

/// Words the app must never use about the user's own data.
const _judgementalWords = <String>[
  'overdue',
  'late',
  'missed',
  'missing',
  'forgot',
  'should have',
  'incomplete',
  'invalid',
  'error',
  'abnormal',
  'irregular',
  'unusual',
  'expected you',
];

void expectNoJudgement(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => (t.data ?? '').toLowerCase())
      .join(' | ');
  for (final word in _judgementalWords) {
    expect(
      texts.contains(word),
      isFalse,
      reason: 'UI used the judgemental word "$word" in: $texts',
    );
  }
}

void main() {
  group('EstimateLine', () {
    testWidgets('says nothing is recorded, rather than flagging a problem',
        (tester) async {
      final stats = computeStats(const []);
      await pumpWidget(tester, EstimateLine(stats: stats));
      expect(find.textContaining('No entries yet'), findsOneWidget);
      expectNoJudgement(tester);
    });

    testWidgets('explains why one entry gives no estimate', (tester) async {
      final stats = computeStats([occ('2025-01-01')]);
      await pumpWidget(tester, EstimateLine(stats: stats));
      expect(find.textContaining('no gap to estimate from'), findsOneWidget);
      expectNoJudgement(tester);
    });

    testWidgets('labels the figure as an estimate and shows a range',
        (tester) async {
      final stats = computeStats([
        occ('2025-01-01'),
        occ('2025-01-29'),
        occ('2025-03-04'),
        occ('2025-03-30'),
      ]);
      await pumpWidget(tester, EstimateLine(stats: stats));
      expect(find.textContaining('Estimated next:'), findsOneWidget);
      expect(find.textContaining('range:'), findsOneWidget);
      expect(find.textContaining('recorded gap'), findsOneWidget);
      expectNoJudgement(tester);
    });

    testWidgets('a long-past estimate is stated neutrally, not as overdue',
        (tester) async {
      // Entries far in the past, so the estimate lands well before today.
      final stats = computeStats([
        occ('2020-01-01'),
        occ('2020-01-29'),
        occ('2020-02-26'),
      ]);
      await pumpWidget(tester, EstimateLine(stats: stats));
      expect(find.textContaining('days ago'), findsWidgets);
      expectNoJudgement(tester);
    });
  });

  group('StatsPanel', () {
    testWidgets('reports entries without an end date as a neutral count',
        (tester) async {
      final stats = computeStats([
        occ('2025-01-01', '2025-01-05'),
        occ('2025-02-01'),
        occ('2025-03-01', '2025-03-04'),
      ]);
      await pumpWidget(
        tester,
        StatsPanel(stats: stats, tracker: _tracker),
      );
      expect(find.text('Without an end date'), findsOneWidget);
      expect(find.text('With an end date'), findsOneWidget);
      expectNoJudgement(tester);
    });

    testWidgets('shows highly variable data without any warning',
        (tester) async {
      final stats = computeStats([
        occ('2025-01-01'),
        occ('2025-01-15'),
        occ('2025-04-01'),
        occ('2025-04-20'),
      ]);
      await pumpWidget(
        tester,
        StatsPanel(stats: stats, tracker: _tracker),
      );
      expect(find.text('Variability'), findsOneWidget);
      expect(find.text('Shortest / longest'), findsWidgets);
      expectNoJudgement(tester);
    });

    testWidgets('omits length rows entirely when nothing has an end',
        (tester) async {
      final stats = computeStats([occ('2025-01-01'), occ('2025-02-01')]);
      await pumpWidget(
        tester,
        StatsPanel(stats: stats, tracker: _tracker),
      );
      expect(find.text('With an end date'), findsNothing);
      expectNoJudgement(tester);
    });
  });
}

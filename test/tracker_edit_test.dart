import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cyclog/models.dart';
import 'package:cyclog/screens/occurrence_edit_screen.dart';
import 'package:cyclog/screens/tracker_edit_screen.dart';

const _singleDay = Tracker(
  id: 1,
  name: 'Single',
  hasDuration: false,
  color: 0xFF1E88E5,
);

Future<void> pumpEdit(WidgetTester tester, {Tracker? existing}) {
  return tester.pumpWidget(
    MaterialApp(home: TrackerEditScreen(existing: existing)),
  );
}

void main() {
  group('Choosing the entry kind', () {
    testWidgets('both options are visible on a new tracker', (tester) async {
      await pumpEdit(tester);
      expect(find.text('What is one entry?'), findsOneWidget);
      expect(find.text('A single day'), findsOneWidget);
      expect(find.text('A stretch of days'), findsOneWidget);
    });

    testWidgets('neither option is preselected on a new tracker',
        (tester) async {
      await pumpEdit(tester);
      expect(find.byIcon(Icons.radio_button_checked), findsNothing);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(2));
    });

    testWidgets('tapping an option selects exactly one', (tester) async {
      await pumpEdit(tester);
      await tester.tap(find.text('A single day'));
      await tester.pump();
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    });

    testWidgets('the options are mutually exclusive', (tester) async {
      await pumpEdit(tester);
      await tester.tap(find.text('A single day'));
      await tester.pump();
      await tester.tap(find.text('A stretch of days'));
      await tester.pump();
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    });

    testWidgets('saving without choosing prompts instead of assuming',
        (tester) async {
      await pumpEdit(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Thing');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Pick one to continue.'), findsOneWidget);
    });

    testWidgets('the prompt clears once an option is picked', (tester) async {
      await pumpEdit(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Thing');
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.tap(find.text('A single day'));
      await tester.pump();
      expect(find.text('Pick one to continue.'), findsNothing);
    });

    testWidgets('an existing tracker shows its current kind selected',
        (tester) async {
      await pumpEdit(tester, existing: _singleDay);
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      expect(find.text('Single'), findsOneWidget);
    });
  });

  group('buildOccurrenceForSave', () {
    // The exact function the entry form calls when saving.
    const spanning = Tracker(
      id: 1,
      name: 'Spanning',
      hasDuration: true,
      color: 0xFF1E88E5,
    );

    test('a single-day tracker keeps an end that was already recorded', () {
      final existing = Occurrence(
        id: 7,
        trackerId: 1,
        start: Day.parse('2025-01-01'),
        end: Day.parse('2025-01-05'),
      );
      final saved = buildOccurrenceForSave(
        tracker: _singleDay,
        existing: existing,
        start: Day.parse('2025-01-02'),
        end: null,
        note: null,
      );
      expect(
        saved.end,
        Day.parse('2025-01-05'),
        reason: 'switching a tracker to single-day must not erase ends',
      );
      expect(saved.start, Day.parse('2025-01-02'));
      expect(saved.id, 7);
    });

    test('a new entry on a single-day tracker has no end', () {
      final saved = buildOccurrenceForSave(
        tracker: _singleDay,
        start: Day.parse('2025-01-02'),
        end: null,
        note: null,
      );
      expect(saved.end, isNull);
      expect(saved.id, isNull);
    });

    test('a spanning tracker stores the chosen end', () {
      final saved = buildOccurrenceForSave(
        tracker: spanning,
        start: Day.parse('2025-01-01'),
        end: Day.parse('2025-01-04'),
        note: null,
      );
      expect(saved.end, Day.parse('2025-01-04'));
      expect(saved.lengthDays, 4);
    });

    test('a spanning tracker can clear an end the user removed', () {
      final existing = Occurrence(
        id: 7,
        trackerId: 1,
        start: Day.parse('2025-01-01'),
        end: Day.parse('2025-01-05'),
      );
      final saved = buildOccurrenceForSave(
        tracker: spanning,
        existing: existing,
        start: Day.parse('2025-01-01'),
        end: null,
        note: null,
      );
      expect(saved.end, isNull);
    });

    test('blank notes are stored as null, not empty strings', () {
      final saved = buildOccurrenceForSave(
        tracker: spanning,
        start: Day.parse('2025-01-01'),
        end: null,
        note: '   ',
      );
      expect(saved.note, isNull);
    });

    test('notes are trimmed but otherwise untouched', () {
      final saved = buildOccurrenceForSave(
        tracker: spanning,
        start: Day.parse('2025-01-01'),
        end: null,
        note: '  heavy, cramps  ',
      );
      expect(saved.note, 'heavy, cramps');
    });
  });

  group('Saving is not blocked by a hidden end date', () {
    // A tracker switched from "stretch of days" to "single day" keeps the
    // ends it already recorded, but no longer shows them. The save guard
    // must not fire on a value the user cannot see or change, or the entry
    // becomes uneditable.
    testWidgets(
        'a single-day entry whose hidden end precedes the start can be saved',
        (tester) async {
      final existing = Occurrence(
        id: 7,
        trackerId: 1,
        start: Day.parse('2025-01-10'),
        end: Day.parse('2025-01-02'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OccurrenceEditScreen(
            tracker: _singleDay,
            existing: existing,
          ),
        ),
      );

      // No end control is offered on a single-day tracker.
      expect(find.text('End'), findsNothing);
      expect(find.text('Date'), findsOneWidget);

      expect(
        find.textContaining('cannot be stored'),
        findsNothing,
        reason: 'the user has no way to resolve a hidden contradiction',
      );
      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.onPressed, isNotNull, reason: 'Save must stay enabled');
    });

    testWidgets('a spanning tracker still blocks an end before the start',
        (tester) async {
      const spanning = Tracker(
        id: 1,
        name: 'Spanning',
        hasDuration: true,
        color: 0xFF1E88E5,
      );
      final existing = Occurrence(
        id: 7,
        trackerId: 1,
        start: Day.parse('2025-01-10'),
        end: Day.parse('2025-01-02'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OccurrenceEditScreen(tracker: spanning, existing: existing),
        ),
      );

      expect(find.textContaining('cannot be stored'), findsOneWidget);
      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.onPressed, isNull, reason: 'Save must be blocked');
    });
  });
}

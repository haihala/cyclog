import 'package:flutter/material.dart';

import '../db.dart';
import '../format.dart';
import '../models.dart';
import '../settings.dart';
import '../stats.dart';
import '../widgets/stat_views.dart';
import 'occurrence_edit_screen.dart';
import 'tracker_edit_screen.dart';

class TrackerScreen extends StatefulWidget {
  const TrackerScreen({super.key, required this.trackerId});

  final int trackerId;

  @override
  State<TrackerScreen> createState() => _TrackerScreenState();
}

class _TrackerScreenState extends State<TrackerScreen> {
  Tracker? _tracker;
  List<Occurrence> _occurrences = const [];
  TrackerStats? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDb.instance;
    final tracker = await db.getTracker(widget.trackerId);
    if (tracker == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final occurrences = await db.getOccurrences(widget.trackerId);
    final settings = Settings.instance;
    final stats = computeStats(
      occurrences,
      level: settings.confidence,
      windowSize: settings.windowOrNull,
    );
    if (!mounted) return;
    setState(() {
      _tracker = tracker;
      _occurrences = occurrences;
      _stats = stats;
      _loading = false;
    });
  }

  Future<void> _addEntry() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OccurrenceEditScreen(tracker: _tracker!),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _editEntry(Occurrence o) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OccurrenceEditScreen(
          tracker: _tracker!,
          existing: o,
        ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _editTracker() async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => TrackerEditScreen(existing: _tracker),
      ),
    );
    if (result == 'deleted') {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tracker = _tracker;
    final stats = _stats;

    if (_loading || tracker == null || stats == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Gap from each entry to the one before it, keyed by occurrence id.
    final gapBefore = <int, int>{};
    final ascending = [..._occurrences]
      ..sort((a, b) => a.start.compareTo(b.start));
    for (var i = 1; i < ascending.length; i++) {
      final id = ascending[i].id;
      if (id != null) {
        gapBefore[id] = ascending[i - 1].start.daysTo(ascending[i].start);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tracker.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Edit tracker',
            onPressed: _editTracker,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addEntry,
        icon: const Icon(Icons.add),
        label: const Text('Add entry'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          if (tracker.notes != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                tracker.notes!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Card(
              margin: EdgeInsets.zero,
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EstimateLine(stats: stats),
                    if (Settings.instance.showEstimates &&
                        stats.nextStart != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'An estimate from your recorded gaps only. '
                        'Nothing here is a prediction about your body.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: StatsPanel(stats: stats, tracker: tracker),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
            child: Text(
              'ENTRIES',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 0.8,
              ),
            ),
          ),
          if (_occurrences.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              child: Text(
                'No entries yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final o in _occurrences)
              _OccurrenceTile(
                occurrence: o,
                tracker: tracker,
                gapBefore: o.id == null ? null : gapBefore[o.id],
                onTap: () => _editEntry(o),
              ),
        ],
      ),
    );
  }
}

class _OccurrenceTile extends StatelessWidget {
  const _OccurrenceTile({
    required this.occurrence,
    required this.tracker,
    required this.gapBefore,
    required this.onTap,
  });

  final Occurrence occurrence;
  final Tracker tracker;
  final int? gapBefore;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final length = occurrence.lengthDays;

    final subtitleParts = <String>[];
    if (tracker.hasDuration) {
      if (occurrence.end != null && length != null) {
        subtitleParts.add('${plural(length, 'day')} long');
      } else {
        subtitleParts.add('no end recorded');
      }
    }
    if (gapBefore != null) {
      subtitleParts.add('${plural(gapBefore!, 'day')} after the previous');
    }

    final title = tracker.hasDuration && occurrence.end != null
        ? formatRange(occurrence.start, occurrence.end!)
        : formatDay(occurrence.start);

    return ListTile(
      dense: false,
      leading: CircleAvatar(
        radius: 5,
        backgroundColor: Color(tracker.color),
      ),
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitleParts.isNotEmpty)
            Text(
              subtitleParts.join(' \u00b7 '),
              style: theme.textTheme.bodySmall,
            ),
          if (occurrence.note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                occurrence.note!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}

import 'package:flutter/material.dart';

import '../db.dart';
import '../format.dart';
import '../models.dart';
import '../settings.dart';
import '../stats.dart';
import '../widgets/stat_views.dart';
import 'settings_screen.dart';
import 'tracker_edit_screen.dart';
import 'tracker_screen.dart';

class _TrackerRow {
  final Tracker tracker;
  final TrackerStats stats;
  const _TrackerRow(this.tracker, this.stats);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<_TrackerRow>? _rows;

  @override
  void initState() {
    super.initState();
    Settings.instance.addListener(_onSettingsChanged);
    _load();
  }

  @override
  void dispose() {
    Settings.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() => _load();

  Future<void> _load() async {
    final db = AppDb.instance;
    final trackers = await db.getTrackers();
    final all = await db.getAllOccurrences();
    final settings = Settings.instance;

    final byTracker = <int, List<Occurrence>>{};
    for (final o in all) {
      byTracker.putIfAbsent(o.trackerId, () => <Occurrence>[]).add(o);
    }

    final rows = <_TrackerRow>[];
    for (final t in trackers) {
      rows.add(
        _TrackerRow(
          t,
          computeStats(
            byTracker[t.id] ?? const <Occurrence>[],
            level: settings.confidence,
            windowSize: settings.windowOrNull,
          ),
        ),
      );
    }
    if (!mounted) return;
    setState(() => _rows = rows);
  }

  Future<void> _addTracker() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const TrackerEditScreen()),
    );
    if (created == true) _load();
  }

  Future<void> _openTracker(Tracker t) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TrackerScreen(trackerId: t.id!)),
    );
    _load();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    _load();
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final rows = _rows;
    if (rows == null) return;
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = rows.removeAt(oldIndex);
      rows.insert(newIndex, item);
    });
    await AppDb.instance.reorderTrackers(
      rows.map((r) => r.tracker).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;

    return Scaffold(
      appBar: AppBar(
        title: const Text('cyclog'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTracker,
        icon: const Icon(Icons.add),
        label: const Text('New tracker'),
      ),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
              ? const _EmptyState()
              : ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 96, top: 4),
                  itemCount: rows.length,
                  onReorder: _reorder,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return _TrackerCard(
                      key: ValueKey(row.tracker.id),
                      tracker: row.tracker,
                      stats: row.stats,
                      onTap: () => _openTracker(row.tracker),
                    );
                  },
                ),
    );
  }
}

class _TrackerCard extends StatelessWidget {
  const _TrackerCard({
    super.key,
    required this.tracker,
    required this.stats,
    required this.onTap,
  });

  final Tracker tracker;
  final TrackerStats stats;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(tracker.color);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 6,
                height: 46,
                margin: const EdgeInsets.only(right: 12, top: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tracker.name,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      stats.lastStart == null
                          ? 'Nothing recorded'
                          : 'Last: ${formatDayCompact(stats.lastStart!)}'
                              ' \u00b7 ${relativeDay(stats.lastStart!)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    EstimateLine(stats: stats, dense: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timeline_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Nothing tracked yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Create a tracker for anything that recurs. '
              'You choose the name and what it means.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

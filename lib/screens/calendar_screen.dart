import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../calendar.dart';
import '../db.dart';
import '../format.dart';
import '../models.dart';
import 'occurrence_edit_screen.dart';

// Fixed metrics. Every month block is the same height, which makes the
// scroll position predictable and lets the view jump straight to a month.
const double _kDayNumberHeight = 26;
const double _kLaneHeight = 10;
const double _kLaneGap = 3;
const double _kWeekBottomPad = 6;
const double _kMonthHeaderHeight = 44;
const double _kWeekdayHeaderHeight = 22;

/// Lanes drawn per week. Beyond this the remaining trackers are hidden from
/// the ribbons; they stay reachable by tapping the day.
const int _kMaxLanes = 6;

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _controller = ScrollController();

  List<Tracker> _trackers = const [];
  Map<int, List<Occurrence>> _byTracker = const {};

  /// Tracker ids the user has hidden from the ribbons.
  final Set<int> _hidden = <int>{};

  bool _loading = true;

  /// Month index 0 is [_firstYear]/[_firstMonth].
  late int _firstYear;
  late int _firstMonth;
  int _monthCount = 1;
  int _todayIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Tracker> get _visibleTrackers =>
      _trackers.where((t) => !_hidden.contains(t.id)).toList();

  int get _laneCount {
    final n = _visibleTrackers.length;
    if (n == 0) return 1;
    return n > _kMaxLanes ? _kMaxLanes : n;
  }

  double get _weekRowHeight =>
      _kDayNumberHeight +
      _laneCount * (_kLaneHeight + _kLaneGap) +
      _kWeekBottomPad;

  double get _monthExtent =>
      _kMonthHeaderHeight +
      _kWeekdayHeaderHeight +
      kWeeksPerMonthGrid * _weekRowHeight;

  Future<void> _load() async {
    final db = AppDb.instance;
    final trackers = await db.getTrackers();
    final all = await db.getAllOccurrences();

    final byTracker = <int, List<Occurrence>>{};
    for (final o in all) {
      byTracker.putIfAbsent(o.trackerId, () => <Occurrence>[]).add(o);
    }

    // Span from a little before the earliest entry to a year ahead, so there
    // is always somewhere to scroll in both directions.
    final today = Day.today();
    var earliest = today;
    for (final o in all) {
      if (o.start < earliest) earliest = o.start;
    }
    final start = addMonths(earliest.year, earliest.month, -3);
    final end = addMonths(today.year, today.month, 12);

    final count = monthsBetween(
          Day(start.year, start.month, 1),
          Day(end.year, end.month, 1),
        ) +
        1;

    if (!mounted) return;
    setState(() {
      _trackers = trackers;
      _byTracker = byTracker;
      _firstYear = start.year;
      _firstMonth = start.month;
      _monthCount = count;
      _todayIndex = monthsBetween(
        Day(start.year, start.month, 1),
        Day(today.year, today.month, 1),
      );
      _loading = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToToday());
  }

  void _jumpToToday() {
    if (!_controller.hasClients) return;
    final target = (_todayIndex * _monthExtent)
        .clamp(0.0, _controller.position.maxScrollExtent);
    _controller.jumpTo(target);
  }

  /// Keeps the same month on screen when the row height changes because
  /// lanes were added or removed.
  void _toggleTracker(int id) {
    final oldExtent = _monthExtent;
    final index =
        _controller.hasClients ? (_controller.offset / oldExtent).round() : 0;

    setState(() {
      if (!_hidden.remove(id)) _hidden.add(id);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) return;
      final target = (index * _monthExtent)
          .clamp(0.0, _controller.position.maxScrollExtent);
      _controller.jumpTo(target);
    });
  }

  Future<void> _openDay(Day day) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _DaySheet(
        day: day,
        trackers: _trackers,
        byTracker: _byTracker,
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final visible = _visibleTrackers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today_outlined),
            tooltip: 'Jump to today',
            onPressed: _jumpToToday,
          ),
        ],
      ),
      body: _trackers.isEmpty
          ? const _NoTrackers()
          : Column(
              children: [
                _Legend(
                  trackers: _trackers,
                  hidden: _hidden,
                  onToggle: _toggleTracker,
                ),
                if (visible.length > _kMaxLanes)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Showing ribbons for the first $_kMaxLanes of '
                        '${visible.length}. Tap a day to see them all.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: _controller,
                    itemCount: _monthCount,
                    itemExtent: _monthExtent,
                    itemBuilder: (context, index) {
                      final ym =
                          addMonths(_firstYear, _firstMonth, index);
                      return _MonthBlock(
                        year: ym.year,
                        month: ym.month,
                        trackers: visible.take(_kMaxLanes).toList(),
                        byTracker: _byTracker,
                        weekRowHeight: _weekRowHeight,
                        onTapDay: _openDay,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.trackers,
    required this.hidden,
    required this.onToggle,
  });

  final List<Tracker> trackers;
  final Set<int> hidden;
  final void Function(int id) onToggle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: trackers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final t = trackers[i];
          final isHidden = hidden.contains(t.id);
          return FilterChip(
            selected: !isHidden,
            showCheckmark: false,
            avatar: CircleAvatar(
              radius: 6,
              backgroundColor:
                  isHidden ? Theme.of(context).disabledColor : Color(t.color),
            ),
            label: Text(t.name),
            onSelected: (_) => onToggle(t.id!),
          );
        },
      ),
    );
  }
}

class _MonthBlock extends StatelessWidget {
  const _MonthBlock({
    required this.year,
    required this.month,
    required this.trackers,
    required this.byTracker,
    required this.weekRowHeight,
    required this.onTapDay,
  });

  final int year;
  final int month;
  final List<Tracker> trackers;
  final Map<int, List<Occurrence>> byTracker;
  final double weekRowHeight;
  final void Function(Day) onTapDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = DateFormat('MMMM yyyy').format(DateTime(year, month));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _kMonthHeaderHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
        SizedBox(
          height: _kWeekdayHeaderHeight,
          child: Row(
            children: [
              for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (final weekStart in monthGridWeeks(year, month))
          _WeekRow(
            weekStart: weekStart,
            year: year,
            month: month,
            trackers: trackers,
            byTracker: byTracker,
            height: weekRowHeight,
            onTapDay: onTapDay,
          ),
      ],
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.weekStart,
    required this.year,
    required this.month,
    required this.trackers,
    required this.byTracker,
    required this.height,
    required this.onTapDay,
  });

  final Day weekStart;
  final int year;
  final int month;
  final List<Tracker> trackers;
  final Map<int, List<Occurrence>> byTracker;
  final double height;
  final void Function(Day) onTapDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = Day.today();

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final colWidth = constraints.maxWidth / kDaysPerWeek;

          return Stack(
            children: [
              // Tap targets and day numbers.
              Row(
                children: [
                  for (var i = 0; i < kDaysPerWeek; i++)
                    Expanded(
                      child: InkWell(
                        onTap: () => onTapDay(weekStart.addDays(i)),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: _DayNumber(
                            day: weekStart.addDays(i),
                            inMonth: isInMonth(
                              weekStart.addDays(i),
                              year,
                              month,
                            ),
                            isToday: weekStart.addDays(i) == today,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              // One lane per tracker, so ribbons line up week to week.
              for (var lane = 0; lane < trackers.length; lane++)
                ..._ribbonsForLane(
                  context: context,
                  tracker: trackers[lane],
                  lane: lane,
                  colWidth: colWidth,
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _ribbonsForLane({
    required BuildContext context,
    required Tracker tracker,
    required int lane,
    required double colWidth,
  }) {
    final occurrences = byTracker[tracker.id] ?? const <Occurrence>[];
    final segments = segmentsForWeek(occurrences, weekStart);
    if (segments.isEmpty) return const [];

    final top = _kDayNumberHeight + lane * (_kLaneHeight + _kLaneGap);
    const capRadius = Radius.circular(_kLaneHeight / 2);
    const flat = Radius.circular(2);

    return [
      for (final s in segments)
        Positioned(
          top: top,
          left: s.startCol * colWidth + 1.5,
          width: s.columnSpan * colWidth - 3,
          height: _kLaneHeight,
          child: Tooltip(
            message: tracker.name,
            child: Container(
              decoration: BoxDecoration(
                color: Color(tracker.color),
                borderRadius: BorderRadius.horizontal(
                  // A flat edge means the entry carries on into the
                  // neighbouring week; a rounded cap means it genuinely
                  // starts or ends here.
                  left: s.continuesBefore ? flat : capRadius,
                  right: s.continuesAfter ? flat : capRadius,
                ),
              ),
            ),
          ),
        ),
    ];
  }
}

class _DayNumber extends StatelessWidget {
  const _DayNumber({
    required this.day,
    required this.inMonth,
    required this.isToday,
  });

  final Day day;
  final bool inMonth;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final color = isToday
        ? scheme.onPrimary
        : inMonth
            ? scheme.onSurface
            : scheme.onSurfaceVariant.withValues(alpha: 0.45);

    return Container(
      margin: const EdgeInsets.only(top: 3),
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: isToday
          ? BoxDecoration(color: scheme.primary, shape: BoxShape.circle)
          : null,
      child: Text(
        day.day.toString(),
        style: theme.textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }
}

/// Everything recorded on one day, with a way to add more.
class _DaySheet extends StatelessWidget {
  const _DaySheet({
    required this.day,
    required this.trackers,
    required this.byTracker,
  });

  final Day day;
  final List<Tracker> trackers;
  final Map<int, List<Occurrence>> byTracker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final entries = <(Tracker, Occurrence)>[];
    for (final t in trackers) {
      for (final o in entriesOnDay(byTracker[t.id] ?? const [], day)) {
        entries.add((t, o));
      }
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(formatDayLong(day), style: theme.textTheme.titleMedium),
            Text(
              relativeDay(day),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Nothing recorded on this day.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final (tracker, o) in entries)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 6,
                          backgroundColor: Color(tracker.color),
                        ),
                        title: Text(tracker.name),
                        subtitle: Text(
                          o.end == null
                              ? 'Starts ${formatDay(o.start)}'
                              : '${formatRange(o.start, o.end!)}'
                                  ' \u00b7 ${plural(o.lengthDays!, 'day')}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final saved = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => OccurrenceEditScreen(
                                tracker: tracker,
                                existing: o,
                              ),
                            ),
                          );
                          if (saved == true && context.mounted) {
                            Navigator.of(context).pop(true);
                          }
                        },
                      ),
                  ],
                ),
              ),
            const Divider(),
            Text(
              'Add an entry on this day',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in trackers)
                  ActionChip(
                    avatar: CircleAvatar(
                      radius: 6,
                      backgroundColor: Color(t.color),
                    ),
                    label: Text(t.name),
                    onPressed: () async {
                      final saved = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => OccurrenceEditScreen(
                            tracker: t,
                            initialStart: day,
                          ),
                        ),
                      );
                      if (saved == true && context.mounted) {
                        Navigator.of(context).pop(true);
                      }
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NoTrackers extends StatelessWidget {
  const _NoTrackers();

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
              Icons.calendar_month_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('Nothing to show yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Create a tracker on the Trackers tab and its entries will '
              'appear here as ribbons.',
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

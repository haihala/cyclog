import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../settings.dart';
import '../stats.dart';

/// A compact, neutral rendering of the next-occurrence estimate.
///
/// Always labelled as an estimate derived from recorded gaps, and always
/// accompanied by how many gaps it is based on, so the user can judge how
/// much weight to give it.
class EstimateLine extends StatelessWidget {
  const EstimateLine({
    super.key,
    required this.stats,
    this.dense = false,
  });

  final TrackerStats stats;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    if (!Settings.instance.showEstimates) {
      return const SizedBox.shrink();
    }

    final est = stats.nextStart;
    if (est == null) {
      return Text(
        stats.occurrenceCount == 0
            ? 'No entries yet'
            : 'One entry so far \u2014 no gap to estimate from',
        style: muted,
      );
    }

    final buffer = StringBuffer()
      ..write('Estimated next: ')
      ..write(formatDayCompact(est.point))
      ..write(' (')
      ..write(relativeDay(est.point))
      ..write(')');

    final children = <Widget>[
      Text(buffer.toString(), style: muted),
    ];

    if (est.hasRange) {
      children.add(
        Text(
          '${est.level.label} range: '
          '${formatRange(est.earliest!, est.latest!)}',
          style: muted,
        ),
      );
    } else {
      children.add(
        Text(
          'Based on a single gap \u2014 no range yet',
          style: muted,
        ),
      );
    }

    if (!dense) {
      children.add(
        Text(
          'From ${plural(est.basedOnGaps, 'recorded gap')}',
          style: muted,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// Full statistics panel for the tracker detail screen.
class StatsPanel extends StatelessWidget {
  const StatsPanel({
    super.key,
    required this.stats,
    required this.tracker,
  });

  final TrackerStats stats;
  final Tracker tracker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final rows = <Widget>[];

    void addRow(String label, String value) {
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 132,
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Text(value, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
        ),
      );
    }

    addRow('Entries', stats.occurrenceCount.toString());

    if (stats.lastStart != null) {
      addRow(
        'Most recent',
        '${formatDay(stats.lastStart!)} (${relativeDay(stats.lastStart!)})',
      );
    }
    if (stats.firstStart != null && stats.occurrenceCount > 1) {
      addRow('First recorded', formatDay(stats.firstStart!));
    }

    if (stats.gaps.n > 0) {
      rows.add(const SizedBox(height: 10));
      rows.add(_SectionLabel('Gap between starts', theme: theme));
      addRow('Average', formatDays(stats.gaps.mean));
      addRow('Median', formatDays(stats.gaps.median));
      if (stats.gaps.n >= 2) {
        addRow('Spread (SD)', formatDays(stats.gaps.stdDev));
      }
      addRow(
        'Shortest / longest',
        '${stats.gaps.min} / ${stats.gaps.max} days',
      );
      addRow('Gaps counted', stats.gaps.n.toString());

      final cv = stats.gapVariability;
      if (cv != null) {
        addRow(
          'Variability',
          '${(cv * 100).toStringAsFixed(0)}% of the average',
        );
      }
    }

    if (tracker.hasDuration && stats.lengths.n > 0) {
      rows.add(const SizedBox(height: 10));
      rows.add(_SectionLabel('Length', theme: theme));
      addRow('Average', formatDays(stats.lengths.mean));
      addRow('Median', formatDays(stats.lengths.median));
      addRow(
        'Shortest / longest',
        '${stats.lengths.min} / ${stats.lengths.max} days',
      );
      addRow('With an end date', stats.lengths.n.toString());
      if (stats.openEndedCount > 0) {
        addRow('Without an end date', stats.openEndedCount.toString());
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

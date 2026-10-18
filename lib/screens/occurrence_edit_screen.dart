import 'package:flutter/material.dart';

import '../db.dart';
import '../format.dart';
import '../models.dart';

/// Add or edit a single entry.
///
/// Dates are never restricted to the past, never pre-filled with guesses
/// beyond today's date as a convenience, and no entry is ever rejected for
/// being "too close", "too far apart" or duplicated. The only thing that
/// blocks saving is an end date placed before its own start date, which is a
/// structural contradiction rather than a judgement about the data.
class OccurrenceEditScreen extends StatefulWidget {
  const OccurrenceEditScreen({
    super.key,
    required this.tracker,
    this.existing,
    this.initialStart,
  });

  final Tracker tracker;
  final Occurrence? existing;

  /// Pre-fills the start date for a new entry, e.g. the day tapped in the
  /// calendar. Only a convenience; the date remains fully editable.
  final Day? initialStart;

  @override
  State<OccurrenceEditScreen> createState() => _OccurrenceEditScreenState();
}

class _OccurrenceEditScreenState extends State<OccurrenceEditScreen> {
  late Day _start;
  Day? _end;
  late final TextEditingController _note;

  bool get _isEditing => widget.existing != null;

  /// Only meaningful while the end is actually editable. On a single-day
  /// tracker the end is hidden and carried through untouched, so blocking the
  /// save would strand the user: the banner would appear with no visible
  /// control to resolve it.
  bool get _endBeforeStart =>
      widget.tracker.hasDuration && _end != null && _end! < _start;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _start = e?.start ?? widget.initialStart ?? Day.today();
    _end = e?.end;
    _note = TextEditingController(text: e?.note ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<Day?> _pickDay(Day initial) async {
    final now = DateTime.now();
    final initialDate = initial.toDateTime();

    // The picker asserts that the initial date sits inside the range. A date
    // from an imported backup can fall outside the default window, so widen
    // the bounds to admit it rather than throwing.
    var first = DateTime(now.year - 50);
    var last = DateTime(now.year + 5);
    if (initialDate.isBefore(first)) first = DateTime(initial.year, 1, 1);
    if (initialDate.isAfter(last)) last = DateTime(initial.year, 12, 31);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null) return null;
    return Day.fromDateTime(picked);
  }

  Future<void> _editStart() async {
    final picked = await _pickDay(_start);
    if (picked == null) return;
    setState(() => _start = picked);
  }

  Future<void> _editEnd() async {
    final picked = await _pickDay(_end ?? _start);
    if (picked == null) return;
    setState(() => _end = picked);
  }

  Future<void> _save() async {
    if (_endBeforeStart) return;

    final occurrence = buildOccurrenceForSave(
      tracker: widget.tracker,
      existing: widget.existing,
      start: _start,
      end: _end,
      note: _note.text,
    );

    if (_isEditing) {
      await AppDb.instance.updateOccurrence(occurrence);
    } else {
      await AppDb.instance.insertOccurrence(occurrence);
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: Text(
          'The entry starting ${formatDay(_start)} will be removed. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await AppDb.instance.deleteOccurrence(widget.existing!.id!);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDuration = widget.tracker.hasDuration;

    final length = (_end != null && !_endBeforeStart)
        ? _start.daysTo(_end!) + 1
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit entry' : 'New entry'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete entry',
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.play_arrow_outlined),
              title: Text(hasDuration ? 'Start' : 'Date'),
              subtitle: Text(
                '${formatDayLong(_start)} \u00b7 ${relativeDay(_start)}',
              ),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _editStart,
            ),
          ),
          if (hasDuration) ...[
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.stop_outlined),
                    title: const Text('End'),
                    subtitle: Text(
                      _end == null
                          ? 'Not recorded'
                          : '${formatDayLong(_end!)} '
                              '\u00b7 ${relativeDay(_end!)}',
                    ),
                    trailing: _end == null
                        ? const Icon(Icons.edit_calendar_outlined)
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Remove end date',
                            onPressed: () => setState(() => _end = null),
                          ),
                    onTap: _editEnd,
                  ),
                  if (_end == null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Leaving the end blank is fine. '
                          'It is kept as-is and simply left out of '
                          'length figures.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (_endBeforeStart)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Card(
                margin: EdgeInsets.zero,
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'The end is earlier than the start, so this entry '
                          'cannot be stored. Adjust either date.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (length != null)
            Padding(
              padding: const EdgeInsets.only(top: 12, left: 4),
              child: Text(
                'Length: ${plural(length, 'day')}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 20),
          TextField(
            controller: _note,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _endBeforeStart ? null : _save,
        backgroundColor: _endBeforeStart
            ? theme.colorScheme.surfaceContainerHighest
            : null,
        icon: const Icon(Icons.check),
        label: const Text('Save'),
      ),
    );
  }
}

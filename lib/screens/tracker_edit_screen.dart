import 'package:flutter/material.dart';

import '../db.dart';
import '../models.dart';

const kTrackerColors = <int>[
  0xFFE53935,
  0xFFD81B60,
  0xFF8E24AA,
  0xFF5E35B1,
  0xFF3949AB,
  0xFF1E88E5,
  0xFF00897B,
  0xFF43A047,
  0xFF7CB342,
  0xFFF9A825,
  0xFFF4511E,
  0xFF6D4C41,
  0xFF546E7A,
];

class TrackerEditScreen extends StatefulWidget {
  const TrackerEditScreen({super.key, this.existing});

  final Tracker? existing;

  @override
  State<TrackerEditScreen> createState() => _TrackerEditScreenState();
}

class _TrackerEditScreenState extends State<TrackerEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _notes;

  /// Null until chosen. New trackers start unset so the choice is made
  /// deliberately rather than inherited from a default the user never saw.
  bool? _spansDays;
  bool _showKindError = false;

  late int _color;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _spansDays = e?.hasDuration;
    _color = e?.color ??
        kTrackerColors[DateTime.now().millisecond % kTrackerColors.length];
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nameOk = _formKey.currentState!.validate();
    final kindOk = _spansDays != null;
    if (!kindOk) setState(() => _showKindError = true);
    if (!nameOk || !kindOk) return;

    setState(() => _saving = true);

    final notes = _notes.text.trim();
    final tracker = Tracker(
      id: widget.existing?.id,
      name: _name.text.trim(),
      hasDuration: _spansDays!,
      color: _color,
      position: widget.existing?.position ?? 0,
      notes: notes.isEmpty ? null : notes,
    );

    if (_isEditing) {
      await AppDb.instance.updateTracker(tracker);
    } else {
      await AppDb.instance.insertTracker(tracker);
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final name = widget.existing!.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text(
          'This permanently deletes the tracker and every entry in it. '
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

    await AppDb.instance.deleteTracker(widget.existing!.id!);
    if (!mounted) return;
    Navigator.of(context).pop('deleted');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit tracker' : 'New tracker'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete tracker',
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            TextFormField(
              controller: _name,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name',
                helperText: 'Call it whatever makes sense to you',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Give it a name' : null,
            ),
            const SizedBox(height: 24),
            Text('What is one entry?', style: theme.textTheme.labelLarge),
            const SizedBox(height: 2),
            Text(
              'You can change this later.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            _KindOption(
              label: 'A single day',
              description:
                  'Each entry is one date, and cyclog tracks the gaps '
                  'between them.',
              icon: Icons.event_outlined,
              selected: _spansDays == false,
              onTap: () => setState(() {
                _spansDays = false;
                _showKindError = false;
              }),
            ),
            const SizedBox(height: 8),
            _KindOption(
              label: 'A stretch of days',
              description:
                  'Each entry has a start, and an end you can add or leave '
                  'blank. Both the gaps between entries and the length of '
                  'each one are tracked.',
              icon: Icons.date_range_outlined,
              selected: _spansDays == true,
              onTap: () => setState(() {
                _spansDays = true;
                _showKindError = false;
              }),
            ),
            if (_showKindError)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Text(
                  'Pick one to continue.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            if (_isEditing) ...[
              const SizedBox(height: 8),
              Text(
                'Switching between these never changes, hides or deletes '
                'anything you have already recorded.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text('Colour', style: theme.textTheme.labelLarge),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in kTrackerColors)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == c
                              ? theme.colorScheme.onSurface
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: _color == c
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 20,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _save,
        icon: const Icon(Icons.check),
        label: const Text('Save'),
      ),
    );
  }
}

/// One of the two mutually exclusive entry kinds, drawn as a full-width
/// card so both options are visible before either is chosen.
class _KindOption extends StatelessWidget {
  const _KindOption({
    required this.label,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? scheme.primary : scheme.outline,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          icon,
                          size: 18,
                          color: selected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: selected
                                ? scheme.onPrimaryContainer
                                : scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: selected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
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

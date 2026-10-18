import 'package:flutter/material.dart';

import '../backup.dart';
import '../db.dart';
import '../format.dart';
import '../settings.dart';
import '../stats.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final path = await exportToFile();
      if (path == null) {
        _toast('Export cancelled.');
      } else {
        _toast('Backup saved.');
      }
    } on Object catch (e) {
      _toast('Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final data = await pickBackupFile();
      if (data == null) {
        _toast('Import cancelled.');
        return;
      }
      if (!mounted) return;

      final mode = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import backup'),
          content: Text(
            'This file contains '
            '${plural(data.trackers.length, 'tracker')} and '
            '${plural(data.occurrences.length, 'entry', 'entries')}.\n\n'
            'Add alongside keeps everything you already have. '
            'Replace deletes all current data first.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('merge'),
              child: const Text('Add alongside'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.of(ctx).pop('replace'),
              child: const Text('Replace all'),
            ),
          ],
        ),
      );

      if (mode == 'merge') {
        await AppDb.instance.mergeIn(data.trackers, data.occurrences);
        _toast('Imported alongside your existing data.');
      } else if (mode == 'replace') {
        await AppDb.instance.replaceAll(data.trackers, data.occurrences);
        _toast('All data replaced with the backup.');
      } else {
        _toast('Import cancelled.');
      }
    } on BackupException catch (e) {
      _toast(e.message);
    } on Object catch (e) {
      _toast('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = Settings.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AnimatedBuilder(
        animation: settings,
        builder: (context, _) {
          return ListView(
            children: [
              _Header('Estimates', theme: theme),
              SwitchListTile(
                value: settings.showEstimates,
                onChanged: _busy
                    ? null
                    : (v) => settings.setShowEstimates(v),
                title: const Text('Show estimates'),
                subtitle: const Text(
                  'Turn off to see only what you have recorded.',
                ),
              ),
              ListTile(
                enabled: settings.showEstimates && !_busy,
                title: const Text('Range width'),
                subtitle: Text(
                  'A ${settings.confidence.label} range. '
                  'Wider ranges are more likely to contain the next date.',
                ),
                trailing: DropdownButton<ConfidenceLevel>(
                  value: settings.confidence,
                  onChanged: settings.showEstimates && !_busy
                      ? (v) {
                          if (v != null) settings.setConfidence(v);
                        }
                      : null,
                  items: [
                    for (final level in ConfidenceLevel.values)
                      DropdownMenuItem(
                        value: level,
                        child: Text(level.label),
                      ),
                  ],
                ),
              ),
              ListTile(
                enabled: settings.showEstimates && !_busy,
                title: const Text('Gaps used'),
                subtitle: Text(
                  settings.window <= 0
                      ? 'Every gap you have recorded.'
                      : 'The most recent ${settings.window} gaps.',
                ),
                trailing: DropdownButton<int>(
                  value: settings.window,
                  onChanged: settings.showEstimates && !_busy
                      ? (v) {
                          if (v != null) settings.setWindow(v);
                        }
                      : null,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('All')),
                    DropdownMenuItem(value: 3, child: Text('3')),
                    DropdownMenuItem(value: 6, child: Text('6')),
                    DropdownMenuItem(value: 12, child: Text('12')),
                    DropdownMenuItem(value: 24, child: Text('24')),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  'Estimates are plain arithmetic on the gaps between the '
                  'entries you made. Nothing is ever added, removed or '
                  'corrected on your behalf, and no entry is ever treated '
                  'as missing or mistaken.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Divider(),
              _Header('Data', theme: theme),
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                title: const Text('Export backup'),
                subtitle: const Text('Save everything as a JSON file.'),
                onTap: _busy ? null : _export,
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Import backup'),
                subtitle: const Text('Read a JSON file saved by cyclog.'),
                onTap: _busy ? null : _import,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Text(
                  'The app itself has no network access and sends nothing '
                  'anywhere. Android\'s own backup does include this app, so '
                  'a copy of your entries can reach your Google account, '
                  'encrypted with your screen lock. Turn that off in Android '
                  'Settings \u2192 System \u2192 Backup if you would rather '
                  'it did not.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (_busy) const LinearProgressIndicator(),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text, {required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
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
